import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/models/playback_shuffle_mode.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/services/playback/library_audio_handler.dart';
import 'package:classipod/core/services/playback/playback_backend.dart';
import 'package:classipod/core/spotify/spotify_api_client.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:classipod/core/spotify/spotify_playback_controller.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/features/menu/providers/music_source_provider.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class FakeSpotifyRemote implements SpotifyRemote {
  final controller = StreamController<SpotifyRemoteEvent>.broadcast();
  final calls = <String>[];
  bool installed = true;
  String? connectError;

  /// Error codes thrown by the next calls to the named command.
  final failures = <String, List<String>>{};

  @override
  Stream<SpotifyRemoteEvent> get events => controller.stream;

  Future<void> _record(String call) async {
    calls.add(call);
    final name = call.split(' ').first;
    final queued = failures[name];
    if (queued != null && queued.isNotEmpty) {
      throw SpotifyException(queued.removeAt(0));
    }
  }

  @override
  Future<bool> isSpotifyInstalled() async => installed;

  /// Completes connections; tests hold it to model the first-time approval
  /// screen that keeps the connection pending.
  Completer<void>? approval;
  String? appRemoteRedirect;

  @override
  Future<void> connect({
    required String clientId,
    required String redirectUri,
    required String appRemoteRedirectUri,
  }) async {
    calls.add('connect');
    appRemoteRedirect = appRemoteRedirectUri;
    await approval?.future;
    if (connectError != null) throw SpotifyException(connectError!);
  }

  /// Tracks of each context in the order the Spotify app plays them, so
  /// commands report the track Spotify would start, as the real app does.
  final contexts = <String, List<String>>{};

  /// Track URIs Spotify will not start on their own; it keeps playing
  /// [stuckOn] instead.
  final refused = <String>{};
  String stuckOn = 'spotify:track:other';

  /// Track URIs whose direct play Spotify ignores without any report.
  final silent = <String>{};

  /// Reported once, before the next command's own report, like Spotify
  /// echoing the old track while it switches.
  String? echoBefore;
  DateTime Function() clock = DateTime.now;

  void _report(String? trackUri) {
    if (trackUri == null) return;
    final echo = echoBefore;
    echoBefore = null;
    if (echo != null) {
      scheduleMicrotask(
        () => controller.add(
          SpotifyPlayerStateEvent(
            SpotifyPlayerState(trackUri: echo, receivedAt: clock()),
          ),
        ),
      );
    }
    scheduleMicrotask(
      () => controller.add(
        SpotifyPlayerStateEvent(
          SpotifyPlayerState(
            trackUri: trackUri,
            isPaused: false,
            receivedAt: clock(),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> disconnect() => _record('disconnect');
  @override
  Future<void> play(String uri) async {
    await _record('play $uri');
    // A whole context may start shuffled, so only single tracks report.
    if (uri.startsWith('spotify:track:') && !silent.contains(uri)) {
      _report(refused.contains(uri) ? stuckOn : uri);
    }
  }

  @override
  Future<void> queue(String uri) => _record('queue $uri');

  @override
  Future<void> skipToIndex(String contextUri, int index) async {
    await _record('skipToIndex $contextUri $index');
    _report(contexts[contextUri]?.elementAtOrNull(index));
  }

  @override
  Future<void> resume() => _record('resume');
  @override
  Future<void> pause() => _record('pause');
  @override
  Future<void> skipNext() => _record('skipNext');
  @override
  Future<void> skipPrevious() => _record('skipPrevious');
  @override
  Future<void> seekTo(Duration position) =>
      _record('seekTo ${position.inMilliseconds}');
  @override
  Future<void> setShuffle(bool enabled) => _record('setShuffle $enabled');
  @override
  Future<void> setRepeat(int mode) => _record('setRepeat $mode');
}

/// Local engine stand-in: records whether the local player is playing.
class LocalPlayer extends Fake implements AudioPlayer {
  final playingEvents = StreamController<bool>.broadcast();
  final loaded = <String>[];

  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Duration position = Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => playingEvents.stream;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loaded.add((source as UriAudioSource).uri.path);
    processingState = ProcessingState.ready;
    return const Duration(seconds: 10);
  }

  @override
  Future<void> play() async {
    playing = true;
    playingEvents.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    playingEvents.add(false);
  }

  @override
  Future<void> stop() async {
    await pause();
    processingState = ProcessingState.idle;
  }

  @override
  Future<void> clearAudioSources() async {
    processingState = ProcessingState.idle;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}
}

class SignedInAuth extends SpotifyAuthController {
  @override
  Future<SpotifyAuthState> build() async =>
      const SpotifyAuthState(SpotifyAuthStatus.signedIn);

  void signOutNow() =>
      state = const AsyncData(SpotifyAuthState(SpotifyAuthStatus.signedOut));
}

MusicMetadata spotifyTrack(String id, int position) => MusicMetadata(
  songId: 'spotify:track:$id',
  trackName: 'Track $id',
  trackArtistNames: const ['Artist'],
  albumName: 'Album',
  trackDuration: 200000,
  originalSongIndex: position,
  isOnDevice: false,
);

MusicMetadata localTrack(String name) =>
    MusicMetadata(songId: name, filePath: '/music/$name.mp3');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSpotifyRemote remote;
  late LocalPlayer player;
  late ProviderContainer container;
  late DateTime now;

  /// Liked Songs the Web API reports, and the requests it received.
  var likedTotal = 120;
  final apiRequests = <String>[];
  final playlist = [
    spotifyTrack('a', 0),
    spotifyTrack('b', 5),
    spotifyTrack('c', 6),
  ];
  const contextUri = 'spotify:playlist:p';

  AudioPlayerServiceNotifier service() =>
      container.read(audioPlayerServiceProvider.notifier);
  NowPlayingModel nowPlaying() => container.read(nowPlayingDetailsProvider);
  PlaybackBackend backend() => container.read(playbackBackendProvider);
  SpotifyPlaybackState spotify() =>
      container.read(spotifyPlaybackControllerProvider);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> emitState(
    String id, {
    bool paused = false,
    int positionMs = 0,
    bool shuffling = false,
    int repeat = 0,
  }) async {
    remote.controller.add(
      SpotifyPlayerStateEvent(
        SpotifyPlayerState(
          trackUri: 'spotify:track:$id',
          trackName: 'Remote $id',
          artists: const ['Someone'],
          albumName: 'Remote Album',
          imageUri: 'spotify:image:abc123',
          durationMs: 200000,
          positionMs: positionMs,
          isPaused: paused,
          isShuffling: shuffling,
          repeatMode: repeat,
          receivedAt: now,
        ),
      ),
    );
    await settle();
  }

  Future<void> playPlaylistTrack(int index) => service().playSpotify(
    tracks: playlist,
    index: index,
    contextUri: contextUri,
    nowPlayingType: NowPlayingType.playlist,
  );

  Future<String> errorCode(Future<void> Function() call) async {
    try {
      await call();
    } on SpotifyException catch (error) {
      return error.code;
    }
    return 'none';
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    likedTotal = 120;
    apiRequests.clear();
    remote = FakeSpotifyRemote()..clock = () => now;
    remote.contexts[contextUri] = [
      for (var i = 0; i <= 6; i++)
        playlist
            .firstWhere(
              (track) => track.originalSongIndex == i,
              orElse: () => spotifyTrack('hidden$i', i),
            )
            .songId!,
    ];
    player = LocalPlayer();
    now = DateTime(2026, 1, 1, 12);
    final handler = LibraryAudioHandler(player);
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        libraryAudioHandlerProvider.overrideWithValue(handler),
        filteredAudioFilesProvider.overrideWith(
          (_) async =>
              UnmodifiableListView([localTrack('one'), localTrack('two')]),
        ),
        spotifyRemoteProvider.overrideWithValue(remote),
        spotifyClockProvider.overrideWithValue(() => now),
        spotifyConfigProvider.overrideWithValue(
          const SpotifyConfig(
            clientId: '0123456789abcdef0123456789abcdef',
            redirectUri: 'retrofy://spotify-callback',
          ),
        ),
        spotifyAuthControllerProvider.overrideWith(SignedInAuth.new),
        spotifyApiProvider.overrideWithValue(
          SpotifyApiClient(
            ({forceRefresh = false}) async => 'token',
            client: MockClient((request) async {
              apiRequests.add(request.url.path);
              final body = switch (request.url.path) {
                '/v1/me/tracks' => {'items': [], 'total': likedTotal},
                '/v1/me' => {'id': 'u1', 'display_name': 'Listener'},
                _ => null,
              };
              return body == null
                  ? http.Response('', 404)
                  : http.Response(jsonEncode(body), 200);
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(audioPlayerServiceProvider.future);
    await container.read(filteredAudioFilesProvider.future);
    await container.read(spotifyAuthControllerProvider.future);
    container.read(nowPlayingDetailsProvider);
    container.read(spotifyPlaybackControllerProvider);
  });

  group('spotify_track_selection', () {
    test('starts the chosen track inside its playlist context', () async {
      await service().setAudioSource(musicMetadataList: [localTrack('one')]);
      await service().play();
      expect(player.playing, isTrue);

      await playPlaylistTrack(1);

      expect(remote.calls, ['connect', 'skipToIndex spotify:playlist:p 5']);
      expect(backend(), PlaybackBackend.spotify);
      expect(player.playing, isFalse, reason: 'local playback yields');
      // Idle, not paused: audio_service then removes Retrofy's media
      // notification so the lock screen shows only Spotify's player.
      expect(
        container
            .read(libraryAudioHandlerProvider)
            .playbackState
            .value
            .processingState,
        AudioProcessingState.idle,
      );
      expect(nowPlaying().currentMetadata, playlist[1]);
      expect(nowPlaying().nowPlayingType, NowPlayingType.playlist);
      expect(nowPlaying().metadataList, playlist);
    });

    test('tracks without a context play on their own', () async {
      await service().playSpotify(tracks: playlist, index: 2);
      expect(remote.calls.last, 'play spotify:track:c');
    });

    test('Shuffle Play starts the whole context shuffled', () async {
      await service().playSpotify(
        tracks: playlist,
        contextUri: contextUri,
        shuffle: true,
      );
      expect(remote.calls, [
        'connect',
        'setShuffle true',
        'play spotify:playlist:p',
      ]);
      expect(nowPlaying().currentMetadata, isNull);
      await emitState('c');
      expect(nowPlaying().currentMetadata, playlist[2]);
      expect(nowPlaying().currentIndex, 2);
    });

    test('a rejected context falls back to the single track', () async {
      remote.failures['skipToIndex'] = ['remote_service'];
      await playPlaylistTrack(0);
      expect(remote.calls.last, 'play spotify:track:a');
      expect(backend(), PlaybackBackend.spotify);
    });

    test('connection reuses one Spotify session', () async {
      await playPlaylistTrack(0);
      await playPlaylistTrack(1);
      expect(remote.calls.where((call) => call == 'connect'), hasLength(1));
    });
  });

  group('spotify_selection_accuracy', () {
    List<MusicMetadata> bigPlaylist(int length) => [
      for (var i = 0; i < length; i++) spotifyTrack('t$i', i),
    ];

    for (final length in [1, 10, 50, 100, 500]) {
      test('first, middle and last of $length tracks play exactly', () async {
        final tracks = bigPlaylist(length);
        const uri = 'spotify:playlist:big';
        remote.contexts[uri] = [for (final track in tracks) track.songId!];
        for (final index in {0, length ~/ 2, length - 1}) {
          await service().playSpotify(
            tracks: tracks,
            index: index,
            contextUri: uri,
          );
          expect(remote.calls.last, 'skipToIndex $uri $index');
          expect(spotify().player?.trackUri, tracks[index].songId);
          expect(nowPlaying().currentMetadata, tracks[index]);
        }
        expect(remote.calls.where((call) => call.startsWith('play ')), isEmpty);
      });
    }

    test('a context that starts another track is corrected', () async {
      // The Spotify app leaves out an item the Web API lists (e.g. an
      // unplayable track), so every later index lands one track too far.
      remote.contexts[contextUri] = [
        for (final id in ['a', 'h1', 'h2', 'h3', 'h4', 'b', 'c'])
          'spotify:track:$id',
      ]..removeAt(1);

      await playPlaylistTrack(1);

      expect(remote.calls.sublist(1), [
        'skipToIndex spotify:playlist:p 5',
        'play spotify:track:b',
      ]);
      expect(spotify().player?.trackUri, 'spotify:track:b');
      expect(nowPlaying().currentMetadata, playlist[1]);
    });

    test('Spotify refusing the chosen track is reported, not hidden', () async {
      remote.contexts[contextUri] = List.filled(7, 'spotify:track:other');
      remote.refused.add('spotify:track:c');

      expect(await errorCode(() => playPlaylistTrack(2)), 'wrong_track');
      expect(
        nowPlaying().currentMetadata,
        isNot(playlist[2]),
        reason: 'Now Playing must not claim the chosen track plays',
      );
    });

    test('shuffle stays as it is when a track is tapped', () async {
      await emitState('a', shuffling: true);
      await playPlaylistTrack(2);
      expect(remote.calls.where((call) => call.startsWith('setShuffle')), []);
      expect(spotify().player?.trackUri, 'spotify:track:c');
      expect(nowPlaying().currentMetadata, playlist[2]);
    });

    test('Spotify ignoring the direct request is reported', () async {
      // Champion's "Be Alright": unplayable here, so Spotify starts the next
      // track for the context and then ignores the track on its own.
      remote.contexts[contextUri] = List.filled(7, 'spotify:track:next');
      remote.silent.add('spotify:track:c');

      expect(await errorCode(() => playPlaylistTrack(2)), 'wrong_track');
      expect(nowPlaying().currentMetadata, isNot(playlist[2]));
    });

    test('re-tapping the playing track waits for Spotify to settle', () async {
      await emitState('c');
      // Spotify repeats the old track once, then starts the next one.
      remote.contexts[contextUri] = List.filled(7, 'spotify:track:next');
      remote.echoBefore = 'spotify:track:c';
      remote.refused.add('spotify:track:c');

      expect(await errorCode(() => playPlaylistTrack(2)), 'wrong_track');
      expect(
        remote.calls.where((call) => call == 'play spotify:track:c'),
        hasLength(1),
        reason: 'the stale report did not count as success',
      );
    });

    test('re-tapping the playing track that Spotify keeps succeeds', () async {
      await emitState('c');
      await playPlaylistTrack(2);
      expect(remote.calls.last, 'skipToIndex spotify:playlist:p 6');
      expect(nowPlaying().currentMetadata, playlist[2]);
    });

    test('switching playlists plays the track of the newest one', () async {
      const other = 'spotify:playlist:other';
      final otherTracks = [spotifyTrack('x', 0), spotifyTrack('y', 1)];
      remote.contexts[other] = ['spotify:track:x', 'spotify:track:y'];
      await playPlaylistTrack(2);
      await service().playSpotify(
        tracks: otherTracks,
        index: 1,
        contextUri: other,
      );
      expect(spotify().player?.trackUri, 'spotify:track:y');
      expect(nowPlaying().currentMetadata, otherTracks[1]);
      expect(nowPlaying().metadataList, otherTracks);
    });
  });

  group('spotify_click_wheel_controls', () {
    setUp(() async {
      await playPlaylistTrack(0);
      await emitState('a');
      remote.calls.clear();
    });

    test('play/pause toggles the Spotify player', () async {
      await service().togglePlayback();
      await emitState('a', paused: true);
      await service().togglePlayback();
      expect(remote.calls, ['pause', 'resume']);
      expect(player.playing, isFalse);
    });

    test('skip buttons and scrubbing control Spotify', () async {
      await service().nextSong();
      await service().seekBackwards();
      await service().seekToDuration(30);
      await service().seekToDuration(99999);
      expect(remote.calls, [
        'skipNext',
        'skipPrevious',
        'seekTo 30000',
        'seekTo 200000',
      ]);
    });

    test('shuffle and repeat map to Spotify modes', () async {
      await service().setShuffleMode(PlaybackShuffleMode.albums);
      await service().setShuffleMode(PlaybackShuffleMode.off);
      await service().setLoopMode(LoopMode.one);
      await service().setLoopMode(LoopMode.all);
      await service().setLoopMode(LoopMode.off);
      expect(remote.calls, [
        'setShuffle true',
        'setShuffle false',
        'setRepeat 1',
        'setRepeat 2',
        'setRepeat 0',
      ]);
    });

    test('stop and sleep timer pause Spotify', () async {
      await service().stop();
      expect(remote.calls, ['pause']);
    });
  });

  group('spotify_state_sync', () {
    setUp(() => playPlaylistTrack(0));

    test('Now Playing mirrors Spotify play state and modes', () async {
      await emitState('a', shuffling: true, repeat: 2);
      expect(nowPlaying().isPlaying, isTrue);
      expect(nowPlaying().shuffleMode, PlaybackShuffleMode.songs);
      expect(nowPlaying().loopMode, LoopMode.all);
      await emitState('a', paused: true);
      expect(nowPlaying().isPlaying, isFalse);
      expect(nowPlaying().loopMode, LoopMode.off);
    });

    test('tracks advanced by Spotify move the selection', () async {
      await emitState('c');
      expect(nowPlaying().currentIndex, 2);
      expect(nowPlaying().currentMetadata, playlist[2]);
    });

    test('tracks beyond the list are described from Spotify', () async {
      await emitState('zzz');
      final current = nowPlaying().currentMetadata!;
      expect(current.songId, 'spotify:track:zzz');
      expect(current.trackName, 'Remote zzz');
      expect(current.thumbnailPath, 'https://i.scdn.co/image/abc123');
      expect(current.isSpotify, isTrue);
    });

    test('progress is interpolated between Spotify updates', () async {
      await emitState('a', positionMs: 10000);
      now = now.add(const Duration(milliseconds: 2500));
      expect(service().displayPosition, const Duration(milliseconds: 12500));
      await emitState('a', positionMs: 15000, paused: true);
      now = now.add(const Duration(seconds: 30));
      expect(service().displayPosition, const Duration(seconds: 15));
    });

    test('the progress ticker runs only while something listens', () async {
      final controller = container.read(
        spotifyPlaybackControllerProvider.notifier,
      );
      await emitState('a', positionMs: 1000);
      var ticks = 0;
      final sub = controller.playbackStates.listen((_) => ticks++);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(ticks, greaterThanOrEqualTo(2), reason: 'ticks while visible');
      await sub.cancel();
      final before = ticks;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(ticks, before);
      // Nothing listens: no periodic timer should remain scheduled.
      final again = controller.playbackStates.listen((_) => ticks++);
      await again.cancel();
    });

    test(
      'the progress ticker stops while Retrofy is in the background',
      () async {
        final controller = container.read(
          spotifyPlaybackControllerProvider.notifier,
        );
        await emitState('a', positionMs: 1000);
        var ticks = 0;
        final sub = controller.playbackStates.listen((_) => ticks++);
        addTearDown(sub.cancel);
        final binding = TestWidgetsFlutterBinding.instance;
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        expect(ticks, greaterThanOrEqualTo(2));

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          binding.handleAppLifecycleStateChanged(state);
        }
        final hiddenAt = ticks;
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        expect(ticks, hiddenAt, reason: 'no ticks in the background');

        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          binding.handleAppLifecycleStateChanged(state);
        }
        await Future<void>.delayed(Duration.zero);
        expect(ticks, hiddenAt + 1, reason: 'fresh position on return');
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        expect(ticks, greaterThan(hiddenAt + 1));
      },
    );

    test('local player events are ignored while Spotify plays', () async {
      await emitState('a');
      player.playingEvents.add(false);
      await settle();
      expect(nowPlaying().isPlaying, isTrue);
    });

    test(
      'ratings of Spotify tracks are never written to the library',
      () async {
        await container
            .read(nowPlayingDetailsProvider.notifier)
            .setCurrentMetadataRating(4);
        expect(nowPlaying().currentMetadata!.rating, 4);
      },
    );
  });

  group('spotify_first_approval', () {
    test('the chosen track plays exactly once after approval', () async {
      remote.approval = Completer<void>();
      final request = playPlaylistTrack(1);
      await settle();
      expect(spotify().connection, SpotifyConnection.connecting);
      expect(remote.calls, ['connect'], reason: 'nothing plays before');
      // A second selection while waiting shares the same connection.
      final again = playPlaylistTrack(1);
      await settle();
      expect(remote.calls, ['connect']);

      remote.approval!.complete();
      await request;
      await again;
      expect(
        remote.calls.where((call) => call.startsWith('skipToIndex')),
        hasLength(2),
        reason: 'one per selection; the screen blocks repeat taps',
      );
      expect(remote.calls.where((call) => call == 'connect'), hasLength(1));
      expect(backend(), PlaybackBackend.spotify);
      expect(nowPlaying().currentMetadata, playlist[1]);
      expect(remote.appRemoteRedirect, SpotifyConfig.appRemoteRedirectUri);
    });

    test('declined approval plays nothing and reports why', () async {
      remote.connectError = 'not_authorized';
      expect(await errorCode(() => playPlaylistTrack(0)), 'not_authorized');
      expect(remote.calls, ['connect']);
      expect(backend(), PlaybackBackend.library);
      expect(nowPlaying().metadataList, isNot(playlist));
    });
  });

  group('spotify_connection', () {
    test('missing Spotify app keeps local playback in charge', () async {
      remote.installed = false;
      expect(await errorCode(() => playPlaylistTrack(0)), 'not_installed');
      expect(backend(), PlaybackBackend.library);
      expect(spotify().error, 'not_installed');
      expect(remote.calls, isEmpty);
    });

    test('connection failures are reported', () async {
      remote.connectError = 'not_logged_in';
      expect(await errorCode(() => playPlaylistTrack(0)), 'not_logged_in');
      expect(spotify().connection, SpotifyConnection.disconnected);
    });

    test('a dropped connection reconnects on the next command', () async {
      await playPlaylistTrack(0);
      await emitState('a', positionMs: 5000);
      remote.controller.add(const SpotifyDisconnectedEvent('disconnected'));
      await settle();
      expect(spotify().connection, SpotifyConnection.disconnected);
      expect(spotify().error, 'disconnected');
      expect(nowPlaying().currentMetadata, playlist[0], reason: 'kept');

      remote.calls.clear();
      await service().nextSong();
      expect(remote.calls, ['connect', 'skipNext']);
    });

    test('a stale connection is retried once', () async {
      await playPlaylistTrack(0);
      remote.calls.clear();
      remote.failures['skipNext'] = ['not_connected'];
      await service().nextSong();
      expect(remote.calls, ['skipNext', 'connect', 'skipNext']);
    });

    test('free accounts may shuffle contexts but not pick tracks', () async {
      await playPlaylistTrack(0);
      remote.controller.add(
        const SpotifyCapabilitiesEvent(canPlayOnDemand: false),
      );
      await settle();
      expect(spotify().canPlayOnDemand, isFalse);
      expect(await errorCode(() => playPlaylistTrack(1)), 'premium_required');
      await service().playSpotify(
        tracks: playlist,
        contextUri: contextUri,
        shuffle: true,
      );
      expect(remote.calls.last, 'play spotify:playlist:p');
    });

    test('pausing without a connection does not launch Spotify', () async {
      await container.read(spotifyPlaybackControllerProvider.notifier).pause();
      expect(remote.calls, isEmpty);
    });

    test('signing out disconnects from the Spotify app', () async {
      await playPlaylistTrack(0);
      (container.read(spotifyAuthControllerProvider.notifier) as SignedInAuth)
          .signOutNow();
      await settle();
      expect(remote.calls.last, 'disconnect');
      expect(spotify().connection, SpotifyConnection.disconnected);
    });
  });

  group('shuffle_my_music', () {
    test(
      'with Spotify as the source, Liked Songs shuffle in Spotify',
      () async {
        await container
            .read(musicSourceProvider.notifier)
            .choose(MusicSource.spotify);
        expect(service().shuffleMyMusicUsesSpotify, isTrue);
        await service().shuffleMyMusic();
        expect(remote.calls, [
          'connect',
          'setShuffle true',
          'play spotify:user:u1:collection',
        ]);
        expect(
          remote.calls,
          isNot(contains('pause')),
          reason: 'Spotify is never paused to shuffle an empty library',
        );
        expect(backend(), PlaybackBackend.spotify);
        expect(player.playing, isFalse);
        // Spotify picks the tracks; Now Playing follows what it reports.
        await emitState('liked7', shuffling: true);
        expect(nowPlaying().currentMetadata?.songId, 'spotify:track:liked7');
        expect(nowPlaying().isShuffleEnabled, isTrue);
        await emitState('liked3', shuffling: true);
        expect(nowPlaying().currentMetadata?.songId, 'spotify:track:liked3');
      },
    );

    test('an empty Liked Songs reports it and plays nothing', () async {
      await container
          .read(musicSourceProvider.notifier)
          .choose(MusicSource.spotify);
      likedTotal = 0;
      expect(await errorCode(service().shuffleMyMusic), 'no_liked_songs');
      expect(remote.calls.where((c) => c.startsWith('play')), isEmpty);
    });

    test('free accounts may shuffle Liked Songs', () async {
      await container
          .read(musicSourceProvider.notifier)
          .choose(MusicSource.spotify);
      remote.controller.add(
        const SpotifyCapabilitiesEvent(canPlayOnDemand: false),
      );
      await settle();
      expect(await errorCode(service().shuffleMyMusic), 'none');
      expect(remote.calls.last, 'play spotify:user:u1:collection');
    });

    test('with the library as the source, local songs shuffle', () async {
      await container
          .read(musicSourceProvider.notifier)
          .choose(MusicSource.library);
      expect(service().shuffleMyMusicUsesSpotify, isFalse);
      await service().shuffleMyMusic();
      expect(remote.calls, isEmpty, reason: 'Spotify is not involved');
      expect(apiRequests, isEmpty);
      expect(backend(), PlaybackBackend.library);
      expect(nowPlaying().shuffleMode, PlaybackShuffleMode.songs);
    });

    test('signed out, Shuffle My Music uses the library', () async {
      await container
          .read(musicSourceProvider.notifier)
          .choose(MusicSource.spotify);
      (container.read(spotifyAuthControllerProvider.notifier) as SignedInAuth)
          .signOutNow();
      expect(service().shuffleMyMusicUsesSpotify, isFalse);
    });
  });

  group('spotify_session_resume', () {
    late SharedPreferencesWithCache prefs;
    const key = 'spotifySessionActive';

    setUp(() async {
      prefs = await container.read(sharedPreferencesWithCacheProvider.future);
    });

    test('playing Spotify is remembered until local music plays', () async {
      await playPlaylistTrack(1);
      await settle();
      expect(prefs.getBool(key), isTrue);
      await service().setAudioSource(musicMetadataList: [localTrack('one')]);
      await settle();
      expect(prefs.getBool(key), isFalse);
    });

    test('a restarted Retrofy shows what Spotify is playing', () async {
      await prefs.setBool(key, true);
      await service().resumeSpotifySession();
      expect(backend(), PlaybackBackend.spotify);
      expect(remote.calls, ['connect']);
      expect(
        remote.calls.where((c) => c.startsWith('play')),
        isEmpty,
        reason: 'resuming never starts playback',
      );
      await emitState('x');
      expect(nowPlaying().currentMetadata?.trackName, 'Remote x');
    });

    test('without a Spotify session nothing reconnects', () async {
      await service().resumeSpotifySession();
      expect(backend(), PlaybackBackend.library);
      expect(remote.calls, isEmpty);
    });
  });

  group('spotify_handoff_to_library', () {
    setUp(() async {
      await playPlaylistTrack(0);
      await emitState('a');
      remote.calls.clear();
    });

    test(
      'playing local music pauses Spotify and restores the engine',
      () async {
        await service().setAudioSource(musicMetadataList: [localTrack('one')]);
        expect(backend(), PlaybackBackend.library);
        expect(remote.calls, ['pause']);
        expect(nowPlaying().currentMetadata!.songId, 'one');

        remote.calls.clear();
        await service().play();
        await service().togglePlayback();
        expect(
          remote.calls,
          isEmpty,
          reason: 'controls go to the local engine',
        );
        expect(player.loaded, ['/music/one.mp3']);
      },
    );

    test(
      'playing a library song from Songs leaves the Spotify queue',
      () async {
        await service().playSongFromLibrary('two');
        expect(backend(), PlaybackBackend.library);
        expect(nowPlaying().currentMetadata!.songId, 'two');
        expect(nowPlaying().metadataList.map((song) => song.songId), [
          'one',
          'two',
        ]);
      },
    );

    test('local songs cannot be handed to the local engine as Spotify', () {
      expect(
        () => spotifyTrack('x', 0).toAudioSource(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
