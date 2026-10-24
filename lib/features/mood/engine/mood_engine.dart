import 'dart:math';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:classipod/features/mood/engine/track_features.dart';
import 'package:classipod/features/mood/models/mood_selection.dart';
import 'package:classipod/features/spotify/providers/spotify_library_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a session's tracks were chosen, shown to the user as-is so an
/// approximate match is never presented as a measured one.
enum MatchBasis {
  /// Measured tempo, energy or valence from a metadata provider.
  audioFeatures,

  /// A playlist of the user's whose name fits the mood.
  playlistName,

  /// Library songs whose genre tags fit the mood.
  genre,

  /// Nothing matched; the user's Liked Songs, shuffled.
  fallbackLikedSongs,

  /// Nothing matched; the whole library, shuffled.
  fallbackLibrary,

  /// Tempo was asked for but no track has BPM data.
  noTempoData,
}

/// A ready-to-play Match Your Mood session.
@immutable
class MoodSession {
  final MoodSelection selection;
  final MatchBasis basis;

  /// Ranked tracks; the first few are the preview. For a [contextUri]
  /// session they are a sample of that context, when it can be listed.
  final List<MusicMetadata> tracks;

  /// A Spotify context to play with Spotify's shuffle, which then owns the
  /// queue. Null when [tracks] themselves are played.
  final String? contextUri;

  /// The playlist the session comes from, for display.
  final String? sourceName;
  final bool spotify;

  const MoodSession({
    required this.selection,
    required this.basis,
    this.tracks = const [],
    this.contextUri,
    this.sourceName,
    required this.spotify,
  });

  bool get canStart => contextUri != null || tracks.isNotEmpty;

  static const previewLength = 8;

  List<MusicMetadata> get preview => tracks.take(previewLength).toList();
}

final _word = RegExp(r'[a-z0-9&]+(?:[-\s][a-z0-9&]+)*');

/// How strongly [name] mentions any of [keywords], as whole words or
/// phrases ("Night Drive" matches "drive", "lo-fi" matches "lo-fi").
int keywordScore(String name, List<String> keywords) {
  final text =
      ' ${_word.allMatches(name.toLowerCase()).map((m) => m[0]).join(' ')} ';
  var score = 0;
  for (final keyword in keywords) {
    if (text.contains(' ${keyword.toLowerCase()} ')) score++;
  }
  return score;
}

/// The user's playlist whose name fits [mood] best, or null if none does.
SpotifyPlaylist? bestPlaylistFor(Mood mood, List<SpotifyPlaylist> playlists) {
  SpotifyPlaylist? best;
  var bestScore = 0;
  for (final playlist in playlists) {
    final score = keywordScore(playlist.name, mood.keywords);
    if (score > bestScore) {
      best = playlist;
      bestScore = score;
    }
  }
  return best;
}

/// Library songs with a genre tag that fits [mood].
List<MusicMetadata> genreMatches(Mood mood, List<MusicMetadata> library) => [
  for (final song in library)
    if (song.genres.any((genre) => keywordScore(genre, mood.genres) > 0)) song,
];

/// Orders [candidates] for [selection] using measured [features] only.
/// Tempo keeps tracks whose BPM lies in the range; mood keeps the closest
/// tracks by valence and energy. Tracks without data are left out, never
/// guessed. The kept tracks are shuffled (Fisher–Yates) so sessions vary,
/// and [recent] tracks go last so a session does not repeat the last one.
List<MusicMetadata> rankByFeatures(
  MoodSelection selection,
  List<MusicMetadata> candidates,
  Map<String, TrackFeatures> features, {
  Set<String> recent = const {},
  Random? random,
  int limit = 60,
}) {
  final kept = <MusicMetadata>[];
  switch (selection) {
    case TempoChoice():
      for (final track in candidates) {
        final tempo = features[track.songId]?.tempo;
        if (tempo != null && selection.contains(tempo)) kept.add(track);
      }
    case MoodChoice(:final mood):
      final scored = <(MusicMetadata, double)>[];
      for (final track in candidates) {
        final f = features[track.songId];
        final valence = f?.valence;
        final energy = f?.energy;
        if (valence == null || energy == null) continue;
        final distance = sqrt(
          pow(valence - mood.valence, 2) + pow(energy - mood.energy, 2),
        );
        if (distance <= 0.3) scored.add((track, distance));
      }
      scored.sort((a, b) => a.$2.compareTo(b.$2));
      kept.addAll(scored.take(limit).map((entry) => entry.$1));
  }
  final fresh = [
    for (final track in kept)
      if (!recent.contains(track.songId)) track,
  ]..shuffle(random);
  final repeated = [
    for (final track in kept)
      if (recent.contains(track.songId)) track,
  ]..shuffle(random);
  return [...fresh, ...repeated].take(limit).toList();
}

/// Tracks played by recent Match Your Mood sessions, kept so the next
/// session prefers other songs.
final moodHistoryProvider = NotifierProvider<MoodHistory, Set<String>>(
  MoodHistory.new,
);

class MoodHistory extends Notifier<Set<String>> {
  static const _capacity = 300;

  @override
  Set<String> build() => const {};

  void addAll(Iterable<String?> ids) {
    final next = {...state, ...ids.whereType<String>()};
    state = next.length <= _capacity
        ? next
        : next.skip(next.length - _capacity).toSet();
  }
}

final trackFeatureSourceProvider = Provider<TrackFeatureSource>(
  (ref) => SpotifyAudioFeatureSource(ref.watch(spotifyApiProvider)),
);

/// Builds a session for [selection] from the active music source: Spotify
/// (Liked Songs first, then the user's playlists) or the local library.
final moodSessionProvider = FutureProvider.autoDispose
    .family<MoodSession, MoodSelection>((ref, selection) async {
      final recent = ref.read(moodHistoryProvider);
      final useSpotify = ref
          .read(audioPlayerServiceProvider.notifier)
          .shuffleMyMusicUsesSpotify;
      if (!useSpotify) {
        final library = await ref.read(filteredAudioFilesProvider.future);
        if (selection is TempoChoice) {
          // Library files are not analysed for BPM, so there is nothing
          // honest to match a tempo against.
          return MoodSession(
            selection: selection,
            basis: MatchBasis.noTempoData,
            spotify: false,
          );
        }
        final mood = (selection as MoodChoice).mood;
        final matches = genreMatches(mood, library);
        return MoodSession(
          selection: selection,
          basis: matches.isEmpty
              ? MatchBasis.fallbackLibrary
              : MatchBasis.genre,
          tracks: _freshFirst(matches.isEmpty ? library : matches, recent),
          spotify: false,
        );
      }

      final liked = await ref.read(spotifyLikedSongsProvider.future);
      final features = await ref.read(trackFeatureSourceProvider).featuresFor([
        for (final track in liked) ?track.songId,
      ]);
      if (features.available) {
        final ranked = rankByFeatures(
          selection,
          liked,
          features.byTrackUri,
          recent: recent,
        );
        if (ranked.isNotEmpty) {
          return MoodSession(
            selection: selection,
            basis: MatchBasis.audioFeatures,
            tracks: ranked,
            spotify: true,
          );
        }
      }
      final auth = await ref.read(spotifyAuthControllerProvider.future);
      final profile = auth.profile ?? await ref.read(spotifyApiProvider).me();
      final likedContext = 'spotify:user:${profile.id}:collection';
      if (selection is TempoChoice) {
        return MoodSession(
          selection: selection,
          basis: MatchBasis.noTempoData,
          spotify: true,
          // Offered as an explicit, labelled alternative only.
          contextUri: likedContext,
          tracks: _freshFirst(liked, recent),
        );
      }
      final mood = (selection as MoodChoice).mood;
      final playlist = bestPlaylistFor(
        mood,
        await ref.read(spotifyPlaylistsProvider.future),
      );
      if (playlist != null) {
        var sample = const <MusicMetadata>[];
        if (playlist.canListItems(profile.id)) {
          try {
            sample = await ref.read(
              spotifyPlaylistTracksProvider(playlist.id).future,
            );
          } catch (_) {
            // The playlist still plays as a whole without a preview.
          }
        }
        return MoodSession(
          selection: selection,
          basis: MatchBasis.playlistName,
          contextUri: playlist.uri,
          sourceName: playlist.name,
          tracks: _freshFirst(sample, recent),
          spotify: true,
        );
      }
      return MoodSession(
        selection: selection,
        basis: MatchBasis.fallbackLikedSongs,
        contextUri: likedContext,
        tracks: _freshFirst(liked, recent),
        spotify: true,
      );
    });

List<MusicMetadata> _freshFirst(
  List<MusicMetadata> tracks,
  Set<String> recent,
) {
  final fresh = [
    for (final track in tracks)
      if (!recent.contains(track.songId)) track,
  ]..shuffle();
  final repeated = [
    for (final track in tracks)
      if (recent.contains(track.songId)) track,
  ]..shuffle();
  return [...fresh, ...repeated];
}

/// Starts [session] and remembers its tracks. Spotify contexts play with
/// Spotify's shuffle; ranked Spotify tracks play in order through Spotify's
/// queue (Premium); library songs play on the local engine.
Future<void> startMoodSession(Ref ref, MoodSession session) async {
  final audio = ref.read(audioPlayerServiceProvider.notifier);
  if (session.spotify && session.contextUri != null) {
    await audio.playSpotify(
      tracks: const [],
      contextUri: session.contextUri,
      shuffle: true,
    );
  } else if (session.spotify) {
    await audio.playSpotifyQueue(session.tracks.take(30).toList());
  } else {
    await audio.setAudioSource(musicMetadataList: session.tracks);
    await audio.play();
  }
  ref
      .read(moodHistoryProvider.notifier)
      .addAll(session.tracks.map((track) => track.songId));
  ref.read(activeMoodSessionProvider.notifier).session = session.selection;
}

/// The Match Your Mood selection that is playing, if any.
final activeMoodSessionProvider =
    NotifierProvider<ActiveMoodSession, MoodSelection?>(ActiveMoodSession.new);

class ActiveMoodSession extends Notifier<MoodSelection?> {
  @override
  MoodSelection? build() => null;

  set session(MoodSelection? value) => state = value;
}

final moodSessionStarterProvider = Provider<Future<void> Function(MoodSession)>(
  (ref) =>
      (session) => startMoodSession(ref, session),
);
