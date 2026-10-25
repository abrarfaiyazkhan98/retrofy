import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/spotify/spotify_api_client.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:classipod/features/mood/engine/mood_engine.dart';
import 'package:classipod/features/mood/engine/track_features.dart';
import 'package:classipod/features/mood/models/mood_selection.dart';
import 'package:classipod/features/spotify/providers/spotify_library_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MusicMetadata track(String id, {List<String> genres = const []}) =>
    MusicMetadata(songId: 'spotify:track:$id', trackName: id, genres: genres);

SpotifyPlaylist playlist(String name, {String owner = 'u1'}) => SpotifyPlaylist(
  id: name.hashCode.toRadixString(16),
  uri: 'spotify:playlist:${name.hashCode}',
  name: name,
  ownerId: owner,
);

class _Audio extends AudioPlayerServiceNotifier {
  _Audio(this.spotify);
  final bool spotify;

  @override
  Future<void> build() async {}

  @override
  bool get shuffleMyMusicUsesSpotify => spotify;
}

class _Auth extends SpotifyAuthController {
  @override
  Future<SpotifyAuthState> build() async => const SpotifyAuthState(
    SpotifyAuthStatus.signedIn,
    profile: SpotifyProfile(id: 'u1', displayName: 'Listener'),
  );
}

class _Features implements TrackFeatureSource {
  _Features([this.result = const TrackFeatureResult.unavailable()]);
  final TrackFeatureResult result;

  @override
  Future<TrackFeatureResult> featuresFor(List<String> trackUris) async =>
      result;
}

void main() {
  group('mood_matching', () {
    test('playlist names match whole words and phrases', () {
      expect(keywordScore('Chill Vibes', Mood.chill.keywords), 1);
      expect(keywordScore('Late Night Drive', Mood.nightDrive.keywords), 3);
      expect(keywordScore('Chilling', Mood.chill.keywords), 0);
      expect(keywordScore('lo-fi beats', Mood.chill.keywords), 1);
    });

    test('the best-named playlist wins; none when nothing fits', () {
      final lists = [playlist('Road Trip'), playlist('Late Night Drive')];
      expect(bestPlaylistFor(Mood.nightDrive, lists)?.name, 'Late Night Drive');
      expect(bestPlaylistFor(Mood.focus, lists), isNull);
    });

    test('library genres match the mood', () {
      final songs = [
        track('a', genres: ['Jazz']),
        track('b', genres: ['Metal']),
        track('c'),
      ];
      expect(genreMatches(Mood.chill, songs).map((s) => s.trackName), ['a']);
    });
  });

  group('mood_ranking', () {
    final songs = [for (var i = 0; i < 6; i++) track('t$i')];
    final features = {
      'spotify:track:t0': const TrackFeatures(
        tempo: 128,
        valence: 0.8,
        energy: 0.7,
      ),
      'spotify:track:t1': const TrackFeatures(
        tempo: 90,
        valence: 0.2,
        energy: 0.3,
      ),
      'spotify:track:t2': const TrackFeatures(
        tempo: 135,
        valence: 0.75,
        energy: 0.72,
      ),
      'spotify:track:t3': const TrackFeatures(valence: 0.8, energy: 0.7),
      // t4 has no data at all; t5 is a slow, sad song.
      'spotify:track:t5': const TrackFeatures(
        tempo: 70,
        valence: 0.1,
        energy: 0.2,
      ),
    };

    test('tempo keeps only measured BPM inside the range', () {
      final ranked = rankByFeatures(
        const TempoChoice(120, 140),
        songs,
        features,
        random: Random(1),
      );
      expect(ranked.map((s) => s.trackName).toSet(), {'t0', 't2'});
    });

    test('tracks without data are never guessed into a match', () {
      final ranked = rankByFeatures(
        const MoodChoice(Mood.happy),
        songs,
        features,
        random: Random(1),
      );
      expect(ranked.map((s) => s.trackName), isNot(contains('t4')));
      expect(ranked.map((s) => s.trackName).toSet(), {'t0', 't2', 't3'});
    });

    test('recently played tracks go last', () {
      for (var seed = 0; seed < 20; seed++) {
        final ranked = rankByFeatures(
          const MoodChoice(Mood.happy),
          songs,
          features,
          recent: {'spotify:track:t0'},
          random: Random(seed),
        );
        expect(ranked.last.trackName, 't0');
      }
    });

    test('the order varies between sessions', () {
      final orders = {
        for (var seed = 0; seed < 20; seed++)
          rankByFeatures(
            const MoodChoice(Mood.happy),
            songs,
            features,
            random: Random(seed),
          ).map((s) => s.trackName).join(),
      };
      expect(orders.length, greaterThan(1));
    });
  });

  group('audio_feature_source', () {
    test('a 403 switches Spotify audio features off for the session', () async {
      var requests = 0;
      final api = SpotifyApiClient(
        ({forceRefresh = false}) async => 'token',
        client: MockClient((request) async {
          requests++;
          return http.Response('{"error":{"status":403}}', 403);
        }),
      );
      final source = SpotifyAudioFeatureSource(api);
      final first = await source.featuresFor(['spotify:track:a']);
      final second = await source.featuresFor(['spotify:track:b']);
      expect(first.available, isFalse);
      expect(second.available, isFalse);
      expect(requests, 1);
    });

    test('measured features are read; a zero tempo means unknown', () async {
      final api = SpotifyApiClient(
        ({forceRefresh = false}) async => 'token',
        client: MockClient((request) async {
          expect(request.url.queryParameters['ids'], 'a,b');
          return http.Response(
            jsonEncode({
              'audio_features': [
                {'id': 'a', 'tempo': 122.5, 'energy': 0.8, 'valence': 0.6},
                {'id': 'b', 'tempo': 0, 'energy': 0.1, 'valence': 0.1},
              ],
            }),
            200,
          );
        }),
      );
      final result = await SpotifyAudioFeatureSource(api)
          .featuresFor(['spotify:track:a', 'spotify:track:b']);
      expect(result.available, isTrue);
      expect(result.byTrackUri['spotify:track:a']?.tempo, 122.5);
      expect(result.byTrackUri['spotify:track:b']?.tempo, isNull);
    });
  });

  group('mood_sessions', () {
    final liked = [track('l1'), track('l2'), track('l3')];

    ProviderContainer spotifyContainer({
      List<SpotifyPlaylist> playlists = const [],
      TrackFeatureResult features = const TrackFeatureResult.unavailable(),
    }) {
      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWith(() => _Audio(true)),
          spotifyAuthControllerProvider.overrideWith(_Auth.new),
          spotifyLikedSongsProvider.overrideWith((_) async => liked),
          spotifyPlaylistsProvider.overrideWith((_) async => playlists),
          spotifyPlaylistTracksProvider.overrideWith(
            (_, _) async => [track('p1'), track('p2')],
          ),
          trackFeatureSourceProvider.overrideWithValue(_Features(features)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('without audio features a mood plays the matching playlist', () async {
      final container = spotifyContainer(
        playlists: [playlist('Gym'), playlist('Sunday Chill')],
      );
      final session = await container.read(
        moodSessionProvider(const MoodChoice(Mood.chill)).future,
      );
      expect(session.basis, MatchBasis.playlistName);
      expect(session.sourceName, 'Sunday Chill');
      expect(session.contextUri, playlist('Sunday Chill').uri);
      expect(session.preview.map((t) => t.trackName).toSet(), {'p1', 'p2'});
    });

    test('no matching playlist is an explicit Liked Songs fallback', () async {
      final container = spotifyContainer(playlists: [playlist('Gym')]);
      final session = await container.read(
        moodSessionProvider(const MoodChoice(Mood.romantic)).future,
      );
      expect(session.basis, MatchBasis.fallbackLikedSongs);
      expect(session.contextUri, 'spotify:user:u1:collection');
    });

    test('tempo without BPM data says so instead of matching', () async {
      final container = spotifyContainer();
      final session = await container.read(
        moodSessionProvider(const TempoChoice(120, 140)).future,
      );
      expect(session.basis, MatchBasis.noTempoData);
    });

    test('with audio features, tempo uses verified BPM only', () async {
      final container = spotifyContainer(
        features: const TrackFeatureResult({
          'spotify:track:l1': TrackFeatures(tempo: 125),
          'spotify:track:l2': TrackFeatures(tempo: 95),
        }),
      );
      final session = await container.read(
        moodSessionProvider(const TempoChoice(120, 140)).future,
      );
      expect(session.basis, MatchBasis.audioFeatures);
      expect(session.tracks.map((t) => t.trackName), ['l1']);
      expect(session.contextUri, isNull);
    });

    test('library tempo is never matched without BPM tags', () async {
      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWith(() => _Audio(false)),
          filteredAudioFilesProvider.overrideWith(
            (_) async => UnmodifiableListView([track('a')]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final tempo = await container.read(
        moodSessionProvider(const TempoChoice(60, 85)).future,
      );
      expect(tempo.basis, MatchBasis.noTempoData);
      expect(tempo.canStart, isFalse);
      final mood = await container.read(
        moodSessionProvider(const MoodChoice(Mood.focus)).future,
      );
      expect(mood.basis, MatchBasis.fallbackLibrary);
      expect(mood.tracks, hasLength(1));
    });
  });
}
