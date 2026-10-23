import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

final spotifyArtworkCacheProvider = Provider<SpotifyArtworkCache>(
  (_) => SpotifyArtworkCache(
    () async =>
        Directory('${(await getApplicationCacheDirectory()).path}/spotify-art'),
  ),
);

final spotifyArtworkProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, url) => ref.read(spotifyArtworkCacheProvider).load(url),
    );

/// Spotify cover art kept on disk so lists and Cover Flow do not refetch it.
/// Bounded by file count; the least recently written files go first.
class SpotifyArtworkCache {
  final Future<Directory> Function() _directory;
  final http.Client _http;
  final int maxFiles;
  final Map<String, Future<Uint8List>> _inFlight = {};
  int _writesSinceTrim = 0;

  SpotifyArtworkCache(
    this._directory, {
    http.Client? client,
    this.maxFiles = 500,
  }) : _http = client ?? http.Client();

  /// Only Spotify's image CDNs are cached, so arbitrary URLs never reach disk.
  static bool handles(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'i.scdn.co' ||
          uri.host == 'mosaic.scdn.co' ||
          uri.host.endsWith('.spotifycdn.com'));

  Future<Uint8List> load(String url) => _inFlight.putIfAbsent(
    url,
    () => _load(url).whenComplete(() {
      unawaited(_inFlight.remove(url));
    }),
  );

  Future<Uint8List> _load(String url) async {
    final directory = await _directory();
    final file = File(
      '${directory.path}/${sha1.convert(utf8.encode(url))}.img',
    );
    try {
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    final response = await _http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').startsWith('image/') ||
        response.bodyBytes.isEmpty) {
      throw const HttpException('artwork');
    }
    try {
      await directory.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      if (++_writesSinceTrim >= 25) {
        _writesSinceTrim = 0;
        await _trim(directory);
      }
    } catch (_) {
      // Caching is best effort; the image is still shown.
    }
    return response.bodyBytes;
  }

  Future<void> _trim(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.img'))
        .cast<File>()
        .toList();
    if (files.length <= maxFiles) return;
    final stamped = [
      for (final file in files)
        (file: file, modified: await file.lastModified()),
    ]..sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in stamped.take(files.length - maxFiles)) {
      try {
        await entry.file.delete();
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
