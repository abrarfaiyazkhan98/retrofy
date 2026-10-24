import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:classipod/core/lyrics/lyrics.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Community synced lyrics from LRCLIB (https://lrclib.net), used for
/// Spotify tracks only. Requests identify Retrofy and send only the track
/// title, artist, album and duration.
class LrclibClient {
  final http.Client _http;
  static const _userAgent =
      'Retrofy/1.0.0 (personal Android music player; '
      'https://github.com/abrarfaiyazkhan98/retrofy)';

  final Future<void> Function(Duration) _wait;

  LrclibClient({http.Client? client, Future<void> Function(Duration)? wait})
    : _http = client ?? http.Client(),
      _wait = wait ?? Future<void>.delayed;

  Future<http.Response> _get(Uri uri) => _http
      .get(uri, headers: const {'User-Agent': _userAgent})
      .timeout(const Duration(seconds: 10));

  /// Returns null when LRCLIB has no lyrics for the track (HTTP 404).
  Future<Lyrics?> lookup(MusicMetadata track) async {
    final title = track.trackName;
    final artist = track.trackArtistNames?.firstOrNull;
    if (title == null || artist == null) return null;
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      'artist_name': artist,
      if (track.albumName != null) 'album_name': track.albumName!,
      // LRCLIB matches durations within about two seconds.
      if (track.getTrackDuration > 0)
        'duration': '${(track.getTrackDuration / 1000).round()}',
    });
    var response = await _get(uri);
    // LRCLIB sheds load with 503 + Retry-After; honour one short retry.
    if (response.statusCode == 503 || response.statusCode == 429) {
      final wait = int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
      if (wait <= 2) {
        await _wait(Duration(seconds: wait));
        response = await _get(uri);
      }
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw HttpException('LRCLIB ${response.statusCode}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map) throw const FormatException('LRCLIB response');
    if (data['instrumental'] == true) {
      return const Lyrics(source: LyricsSource.lrclib, instrumental: true);
    }
    final synced = data['syncedLyrics'];
    final plain = data['plainLyrics'];
    if (synced is! String || synced.trim().isEmpty) {
      // The exact entry may only have plain lyrics while another entry of
      // the same recording (a single, a compilation) is synced.
      final other = await _syncedElsewhere(title, artist, track);
      if (other != null) return other;
    }
    final lyrics =
        Lyrics.parse(synced is String ? synced : null, LyricsSource.lrclib) ??
        Lyrics.parse(plain is String ? plain : null, LyricsSource.lrclib);
    return lyrics;
  }

  /// Synced lyrics from another LRCLIB entry with the same title and artist
  /// whose duration is within two seconds of [track]'s. Failures here are
  /// ignored: the plain lyrics already found are shown instead.
  Future<Lyrics?> _syncedElsewhere(
    String title,
    String artist,
    MusicMetadata track,
  ) async {
    final seconds = track.getTrackDuration / 1000;
    if (seconds <= 0) return null;
    try {
      final response = await _get(
        Uri.https('lrclib.net', '/api/search', {
          'track_name': title,
          'artist_name': artist,
        }),
      );
      if (response.statusCode != 200) return null;
      final results = jsonDecode(utf8.decode(response.bodyBytes));
      if (results is! List) return null;
      for (final entry in results) {
        if (entry is! Map) continue;
        final duration = entry['duration'];
        final synced = entry['syncedLyrics'];
        if (duration is num &&
            (duration - seconds).abs() <= 2 &&
            synced is String) {
          final lyrics = Lyrics.parse(synced, LyricsSource.lrclib);
          if (lyrics != null && lyrics.isSynced) return lyrics;
        }
      }
    } catch (_) {}
    return null;
  }

  void close() => _http.close();
}

final lrclibClientProvider = Provider<LrclibClient>((ref) {
  final client = LrclibClient();
  ref.onDispose(client.close);
  return client;
});

/// Results per track for this session, including misses, so a track is
/// looked up at most once. Bounded to recently played tracks.
class _LyricsCache {
  static const _capacity = 64;
  final _entries = <String, Lyrics?>{};

  bool contains(String key) => _entries.containsKey(key);

  Lyrics? operator [](String key) {
    final value = _entries.remove(key);
    _entries[key] = value;
    return value;
  }

  void operator []=(String key, Lyrics? value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > _capacity) _entries.remove(_entries.keys.first);
  }
}

final _lyricsCacheProvider = Provider<_LyricsCache>((_) => _LyricsCache());

/// Reads the `.lrc` file next to a local track, if the platform allows it.
final lrcFileReaderProvider = Provider<Future<String?> Function(String)>(
  (_) => (audioPath) async {
    if (kIsWeb) return null;
    final dot = audioPath.lastIndexOf('.');
    if (dot <= audioPath.lastIndexOf('/')) return null;
    final file = File('${audioPath.substring(0, dot)}.lrc');
    try {
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      // Storage permissions may hide non-audio files; treat as absent.
      return null;
    }
  },
);

/// Lyrics for [track], preferring synced sources:
/// 1. embedded tag lyrics (synced when they carry LRC timestamps),
/// 2. a `.lrc` file beside a local track,
/// 3. LRCLIB, for Spotify tracks.
///
/// A failed LRCLIB lookup (offline, 503) is not cached and is retried after
/// [lyricsRetryDelay] while the track is on screen.
const lyricsRetryDelay = Duration(seconds: 30);

final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, MusicMetadata>((
  ref,
  track,
) async {
  final embedded = Lyrics.parse(track.lyrics, LyricsSource.embedded);
  if (embedded != null && embedded.isSynced) return embedded;

  final path = track.filePath;
  if (track.isOnDevice && path != null) {
    final file = await ref.read(lrcFileReaderProvider)(path);
    final fromFile = Lyrics.parse(file, LyricsSource.lrcFile);
    if (fromFile != null && (fromFile.isSynced || embedded == null)) {
      return fromFile;
    }
  }
  if (!track.isSpotify) return embedded;

  final cache = ref.read(_lyricsCacheProvider);
  final key = track.identity;
  if (cache.contains(key)) return cache[key];
  try {
    final found = await ref.read(lrclibClientProvider).lookup(track);
    cache[key] = found;
    return found;
  } catch (error) {
    // Offline or LRCLIB unavailable: show none now, retry another time.
    // HttpException carries only the status code; no track details.
    debugPrint(
      'Lyrics lookup failed: ${error is HttpException ? error.message : error.runtimeType}',
    );
    // While the track is still shown, try again a little later; the timer
    // dies with the provider, so nothing polls once the track changes.
    final retry = Timer(lyricsRetryDelay, ref.invalidateSelf);
    ref.onDispose(retry.cancel);
    return null;
  }
});
