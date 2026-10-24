import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:classipod/core/constants/keys.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/models/playback_shuffle_mode.dart';
import 'package:classipod/core/models/shared_preference_keys.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:classipod/core/services/playback/library_audio_handler.dart';
import 'package:classipod/core/services/playback/playback_backend.dart';
import 'package:classipod/core/services/playback/playback_session.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_playback_controller.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/core/subsonic/subsonic_controller.dart';
import 'package:classipod/features/menu/providers/music_source_provider.dart';
import 'package:classipod/features/music/album/models/album_model.dart';
import 'package:classipod/features/music/playlist/models/playlist_model.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/settings/widgets/subsonic_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart';

final audioPlayerProvider = Provider<AudioPlayer>((_) {
  return AudioPlayer();
});

final libraryAudioHandlerProvider = Provider<LibraryAudioHandler>((ref) {
  final handler = LibraryAudioHandler(
    ref.read(audioPlayerProvider),
    resolveSource: (song) async {
      if (!song.isSubsonic) return song.toAudioSource() as UriAudioSource;
      final remote = ref.read(subsonicControllerProvider).value;
      final context = rootNavigatorKey.currentContext;
      if (remote?.enabled == true &&
          remote?.signedIn != true &&
          context != null) {
        await showSubsonicDialog(context);
      }
      return ref.read(subsonicControllerProvider.notifier).resolve(song);
    },
  );
  ref.listen(
    subsonicControllerProvider.select(
      (value) => (value.value?.enabled, value.value?.config?.id),
    ),
    (_, _) => _reconcileLibrary(ref, handler),
  );
  ref.onDispose(() => unawaited(handler.dispose()));
  return handler;
});

void _reconcileLibrary(Ref ref, LibraryAudioHandler handler) {
  if (handler.restoringSession) return;
  // Library changes never touch a Spotify queue.
  if (ref.read(playbackBackendProvider) == PlaybackBackend.spotify) return;
  final now = ref.read(nowPlayingDetailsProvider);
  final remote = ref.read(subsonicControllerProvider).value;
  final library = ref.read(filteredAudioFilesProvider).value;
  final songs = now.nowPlayingType == NowPlayingType.songs && library != null
      ? library.toList()
      : now.metadataList;
  final retained = songs
      .where(
        (song) =>
            !song.isSubsonic ||
            (remote?.enabled == true && remote?.config?.id == song.serverId),
      )
      .toList();
  if (listEquals(now.metadataList, retained)) return;
  ref.read(nowPlayingDetailsProvider.notifier).reconcileMetadata(retained);
  unawaited(handler.reconcileSongs(retained));
}

final audioPlayerServiceProvider =
    AsyncNotifierProvider<AudioPlayerServiceNotifier, void>(
      AudioPlayerServiceNotifier.new,
    );

class AudioPlayerServiceNotifier extends AsyncNotifier<void> {
  AudioPlayerServiceNotifier() : super();

  bool _sessionRestored = false;

  bool get _spotifyActive =>
      ref.read(playbackBackendProvider) == PlaybackBackend.spotify;

  SpotifyPlaybackController get _spotify =>
      ref.read(spotifyPlaybackControllerProvider.notifier);

  /// Position of whichever engine owns Now Playing.
  Duration get displayPosition => _spotifyActive
      ? _spotify.position
      : ref.read(libraryAudioHandlerProvider).displayPosition;

  /// Hands Now Playing back to the local engine before a library item plays.
  /// The Spotify queue is cleared because the local engine cannot play it.
  Future<void> _useLibrary() async {
    if (!_spotifyActive) return;
    unawaited(_rememberSpotifySession(active: false));
    ref.read(playbackBackendProvider.notifier).backend =
        PlaybackBackend.library;
    ref
        .read(nowPlayingDetailsProvider.notifier)
        .setNewMetadataList(
          nowPlayingType: NowPlayingType.songs,
          newMetadataList: const [],
        );
    try {
      await _spotify.pause();
    } catch (_) {}
  }

  /// Whether Spotify was what Retrofy played last, so a restarted Retrofy
  /// can show Spotify's playback again instead of an empty Now Playing.
  Future<void> _rememberSpotifySession({required bool active}) async {
    await ref
        .read(sharedPreferencesWithCacheProvider)
        .value
        ?.setBool(SharedPreferencesKeys.spotifySessionActive.name, active);
  }

  /// After Retrofy restarts, reconnects Now Playing to the Spotify app when
  /// Spotify was the last thing played through Retrofy. Spotify's own player
  /// state then describes the track; nothing starts or stops playing.
  Future<void> resumeSpotifySession() async {
    final active = ref
        .read(sharedPreferencesWithCacheProvider)
        .value
        ?.getBool(SharedPreferencesKeys.spotifySessionActive.name);
    if (active != true || _spotifyActive) return;
    try {
      final auth = await ref.read(spotifyAuthControllerProvider.future);
      if (!auth.signedIn) return;
    } catch (_) {
      return;
    }
    ref.read(playbackBackendProvider.notifier).backend =
        PlaybackBackend.spotify;
    ref
        .read(nowPlayingDetailsProvider.notifier)
        .setSpotifyQueue(
          nowPlayingType: NowPlayingType.songs,
          tracks: const [],
        );
    try {
      await _spotify.ensureConnected();
    } catch (error) {
      // The Spotify app may be missing or signed out; Now Playing shows
      // the reason the next time Spotify is used.
      debugPrint('Spotify session not resumed: $error');
    }
  }

  /// Starts [track], inside [contextUri] when given so Spotify continues
  /// through it, then checks that Spotify really plays that track. A context
  /// that starts a different track is replaced by the chosen track on its
  /// own; if Spotify still plays something else the caller gets
  /// `wrong_track` rather than a silent substitution.
  Future<void> _playSpotifyTrack(
    MusicMetadata track,
    String? contextUri, {
    List<MusicMetadata> listed = const [],
  }) async {
    final uri = track.songId!;
    if (contextUri != null) {
      try {
        final mark = _spotify.requestMark;
        await _spotify.playContext(contextUri, track.originalSongIndex);
        final reported = await _spotify.confirmTrack(uri, mark: mark);
        if (reported == null || reported == uri) return;
        final shown = listed.indexWhere((t) => t.songId == reported);
        debugPrint(
          'Spotify started $reported instead of $uri at '
          '${track.originalSongIndex} of $contextUri '
          '(listed at position '
          '${shown < 0 ? 'none' : listed[shown].originalSongIndex}, '
          'shuffling ${_spotify.state.player?.isShuffling}); '
          'playing it directly',
        );
      } on SpotifyException catch (error) {
        // The Spotify app rejected the context itself (e.g. an unsupported
        // collection URI): start the chosen track on its own instead.
        if (error.code != 'remote_service' && error.code != 'unknown') {
          rethrow;
        }
      }
    }
    final mark = _spotify.requestMark;
    await _spotify.playUri(uri);
    final reported = await _spotify.confirmTrack(uri, mark: mark);
    if (reported != null && reported != uri) {
      debugPrint('Spotify plays $reported after requesting $uri');
      throw const SpotifyException('wrong_track');
    }
  }

  /// Plays Spotify tracks in the Spotify app and shows them in Now Playing.
  /// With [contextUri] (album, playlist or liked songs) Spotify continues
  /// through that context; otherwise just the chosen track is started.
  /// Plays Spotify content in the Spotify app and shows [tracks] in Now
  /// Playing. With [index], that track starts, inside [contextUri] when given
  /// so Spotify continues through the album, playlist or Liked Songs. Without
  /// [index] the whole [contextUri] plays, where Spotify picks the start.
  Future<void> playSpotify({
    required List<MusicMetadata> tracks,
    int? index,
    String? contextUri,
    bool? shuffle,
    NowPlayingType nowPlayingType = NowPlayingType.songs,
  }) async {
    if (index == null ? contextUri == null : index >= tracks.length) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (shuffle != null) await _spotify.setShuffle(shuffle);
      if (index == null) {
        await _spotify.playUri(contextUri!);
      } else {
        await _playSpotifyTrack(tracks[index], contextUri, listed: tracks);
      }
      if (!_spotifyActive) {
        // Stop rather than pause: a paused session keeps Retrofy's media
        // notification, which would show a second, stale player on the lock
        // screen and AOD next to Spotify's. Idle removes it.
        await ref.read(libraryAudioHandlerProvider).stop();
        ref.read(playbackBackendProvider.notifier).backend =
            PlaybackBackend.spotify;
      }
      ref
          .read(nowPlayingDetailsProvider.notifier)
          .setSpotifyQueue(
            nowPlayingType: nowPlayingType,
            tracks: tracks,
            index: index,
          );
      unawaited(_rememberSpotifySession(active: true));
    });
    final error = state.error;
    if (error != null) Error.throwWithStackTrace(error, state.stackTrace!);
  }

  /// Plays [tracks] in this order in the Spotify app: the first starts and
  /// the rest join Spotify's queue. Needs Premium (track choice).
  Future<void> playSpotifyQueue(List<MusicMetadata> tracks) async {
    if (tracks.isEmpty) return;
    await playSpotify(tracks: tracks, index: 0);
    for (final track in tracks.skip(1)) {
      await _spotify.queue(track.songId!);
    }
  }

  @override
  Future<void> build() async {
    final handler = ref.watch(libraryAudioHandlerProvider);
    ref.listen(filteredAudioFilesProvider, (previous, next) {
      if (next.hasValue && previous?.value != next.value) {
        _reconcileLibrary(ref, handler);
      }
    });
  }

  Future<void> restoreSession(List<MusicMetadata> library) async {
    final handler = ref.read(libraryAudioHandlerProvider);
    if (_sessionRestored) {
      _reconcileLibrary(ref, handler);
      return;
    }
    handler.restoringSession = true;
    try {
      PlaybackSessionStore? store;
      try {
        store = PlaybackSessionStore(
          await Hive.openBox<dynamic>('playback-session-v1'),
        );
      } catch (error) {
        debugPrint('Could not open playback session: ${error.runtimeType}');
      }
      final initialRepeatMode = handler.playbackState.value.repeatMode;
      final savedSession = store?.read();
      final session =
          savedSession != null &&
              library.any(
                (song) => song.identity == savedSession.ids[savedSession.index],
              )
          ? savedSession
          : null;
      if (savedSession != null && session == null) await store?.clear();
      final restored = session?.resolve(library);
      final songs = restored?.songs ?? library;
      ref
          .read(nowPlayingDetailsProvider.notifier)
          .setNewMetadataList(
            nowPlayingType: session?.type ?? NowPlayingType.songs,
            newMetadataList: songs,
          );
      await handler.restoreSongs(
        songs,
        index: restored?.index ?? 0,
        position: Duration.zero,
        resetOnFailure: session != null,
      );
      if (session != null) {
        await handler.setShuffleMode(session.shuffle.audioServiceMode);
        await handler.setRepeatMode(switch (session.loop) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        });
      }
      handler.onRestoreFailure = () {
        handler.onCheckpoint = null;
        unawaited(_resetRestoredSession(handler, store, initialRepeatMode));
      };
      ref.onDispose(() => handler.onRestoreFailure = null);
      if (store != null) {
        store.attach(
          handler,
          () => ref.read(nowPlayingDetailsProvider).nowPlayingType,
        );
        ref.onDispose(() {
          handler.onCheckpoint = null;
          unawaited(store!.dispose());
        });
      }
      _sessionRestored = true;
    } finally {
      handler.restoringSession = false;
    }
  }

  Future<void> _resetRestoredSession(
    LibraryAudioHandler handler,
    PlaybackSessionStore? store,
    AudioServiceRepeatMode initialRepeatMode,
  ) async {
    await store?.clear();
    if (!ref.mounted) return;
    final library =
        ref.read(filteredAudioFilesProvider).value?.toList() ??
        <MusicMetadata>[];
    ref
        .read(nowPlayingDetailsProvider.notifier)
        .setNewMetadataList(
          nowPlayingType: NowPlayingType.songs,
          newMetadataList: library,
        );
    try {
      await handler.setSongs(library, preload: false);
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      await handler.setRepeatMode(initialRepeatMode);
    } catch (error) {
      debugPrint('Could not reset playback: ${error.runtimeType}');
    } finally {
      if (ref.mounted) {
        store?.attach(
          handler,
          () => ref.read(nowPlayingDetailsProvider).nowPlayingType,
        );
      }
    }
  }

  Future<void> play() async {
    state = await AsyncValue.guard(_play);
  }

  Future<void> _play() async {
    if (_spotifyActive) return _spotify.resume();
    final handler = ref.read(libraryAudioHandlerProvider);
    if (ref.read(audioPlayerProvider).playing &&
        handler.playbackState.value.errorCode == null &&
        !handler.recovering) {
      return;
    }

    await handler.play();
  }

  Future<void> pause() async {
    if (_spotifyActive) return _spotify.pause();
    await ref.read(libraryAudioHandlerProvider).pause();
  }

  Future<void> stop() async {
    if (_spotifyActive) return _spotify.pause();
    await ref.read(libraryAudioHandlerProvider).stop();
  }

  Future<void> toggleShuffleMode() async {
    await setShuffleMode(
      _spotifyActive
          ? ref.read(nowPlayingDetailsProvider).shuffleMode.next
          : ref.read(libraryAudioHandlerProvider).logicalQueue.shuffleMode.next,
    );
  }

  Future<void> setShuffleMode(PlaybackShuffleMode mode) async {
    state = await AsyncValue.guard(() async {
      // Spotify shuffles a whole context; album shuffle maps to on.
      if (_spotifyActive) {
        return _spotify.setShuffle(mode != PlaybackShuffleMode.off);
      }
      final handler = ref.read(libraryAudioHandlerProvider);
      await handler.setShuffleMode(mode.audioServiceMode);
    });
  }

  Future<void> shuffleAllSongs() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _useLibrary();
      //If Album or Playlist is being played then Switch to original List of Songs
      if (ref.read(nowPlayingDetailsProvider).nowPlayingType !=
              NowPlayingType.songs ||
          ref.read(nowPlayingDetailsProvider).metadataList.isEmpty) {
        await setAudioSource(
          musicMetadataList: ref.read(filteredAudioFilesProvider).requireValue,
        );
      }

      await setShuffleMode(PlaybackShuffleMode.songs);
      await nextSong();
      Future.delayed(const Duration(milliseconds: 100), play);

      await ref
          .read(settingsPreferencesControllerProvider.notifier)
          .setInitialRepeatMode();
    });
  }

  /// Whether Shuffle My Music uses Spotify: when Spotify is the Music
  /// source, or when there is no local library to shuffle.
  bool get shuffleMyMusicUsesSpotify {
    final signedIn =
        ref.read(spotifyAuthControllerProvider).value?.signedIn ?? false;
    if (!signedIn) return false;
    final library = ref.read(filteredAudioFilesProvider).value ?? const [];
    return ref.read(musicSourceProvider) == MusicSource.spotify ||
        library.isEmpty;
  }

  /// Shuffle My Music: the user's Spotify Liked Songs, or every library
  /// song. Throws [SpotifyException] when Spotify cannot start it.
  Future<void> shuffleMyMusic() => shuffleMyMusicUsesSpotify
      ? shuffleSpotifyLikedSongs()
      : shuffleAllSongs();

  /// Plays the signed-in user's Liked Songs with Spotify's own shuffle.
  /// Spotify owns that queue, so Retrofy never builds a competing one; it
  /// only mirrors the tracks the Spotify app reports.
  Future<void> shuffleSpotifyLikedSongs() async {
    final auth = await ref.read(spotifyAuthControllerProvider.future);
    if (!auth.signedIn) throw const SpotifyException('signin');
    final api = ref.read(spotifyApiProvider);
    if (await api.savedTrackCount() == 0) {
      throw const SpotifyException('no_liked_songs');
    }
    final profile = auth.profile ?? await api.me();
    await playSpotify(
      tracks: const [],
      contextUri: 'spotify:user:${profile.id}:collection',
      shuffle: true,
    );
  }

  Future<void> setLoopMode(LoopMode loopMode) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (_spotifyActive) {
        return _spotify.setRepeat(switch (loopMode) {
          LoopMode.off => SpotifyPlayerState.repeatOff,
          LoopMode.one => SpotifyPlayerState.repeatOne,
          LoopMode.all => SpotifyPlayerState.repeatAll,
        });
      }
      await ref.read(libraryAudioHandlerProvider).setRepeatMode(
        switch (loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      );
    });
  }

  Future<void> setAudioSource({
    NowPlayingType nowPlayingType = NowPlayingType.songs,
    bool preload = true,
    required List<MusicMetadata> musicMetadataList,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _useLibrary();
      ref
          .read(nowPlayingDetailsProvider.notifier)
          .setNewMetadataList(
            nowPlayingType: nowPlayingType,
            newMetadataList: musicMetadataList,
          );

      await ref
          .read(libraryAudioHandlerProvider)
          .setSongs(musicMetadataList, preload: preload);
    });
  }

  Future<void> nextSong() async {
    state = await AsyncValue.guard(
      () => _spotifyActive
          ? _spotify.skipNext()
          : ref.read(libraryAudioHandlerProvider).skipToNext(),
    );
  }

  Future<void> seekBackwards() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (_spotifyActive) return _spotify.skipPrevious();
      await ref.read(libraryAudioHandlerProvider).skipToPrevious();
    });
  }

  Future<void> playAlbum({
    required AlbumModel albumDetail,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // If Album has no songs or the songIndex is out of bounds
      if (albumDetail.albumSongs.isEmpty ||
          songIndex >= albumDetail.albumSongs.length) {
        return;
      }
      await _useLibrary();
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);

      // If the album is already playing
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.album &&
          nowPlayingDetails.currentMetadata?.getAlbumDetail == albumDetail) {
        await playSongAtIndex(songIndex);
        return;
      } else {
        await setAudioSource(
          preload: false,
          nowPlayingType: NowPlayingType.album,
          musicMetadataList: albumDetail.albumSongs,
        );
        await playSongAtIndex(songIndex);
        Future.delayed(const Duration(milliseconds: 100), play);
      }
    });
  }

  Future<void> playPlaylist({
    required PlaylistModel playlistDetail,
    required int songIndex,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // If Playlist has no songs or the songIndex is out of bounds
      if (playlistDetail.songs.isEmpty ||
          songIndex >= playlistDetail.songs.length) {
        return;
      }
      await _useLibrary();
      final nowPlayingDetails = ref.read(nowPlayingDetailsProvider);

      // If the playlist is already playing
      if (nowPlayingDetails.nowPlayingType == NowPlayingType.playlist &&
          listEquals(nowPlayingDetails.metadataList, playlistDetail.songs)) {
        await playSongAtIndex(songIndex);
        return;
      } else {
        await setAudioSource(
          preload: false,
          nowPlayingType: NowPlayingType.playlist,
          musicMetadataList: playlistDetail.songs,
        );
        await playSongAtIndex(songIndex);
        Future.delayed(const Duration(milliseconds: 100), play);
      }
    });
  }

  Future<void> playSongAtIndex(int index) async {
    state = await AsyncValue.guard(() async {
      if (ref.read(nowPlayingDetailsProvider).currentIndex == index) {
        await _play();
      } else {
        await ref.read(libraryAudioHandlerProvider).select(index);
      }
    });
  }

  Future<void> playSongFromLibrary(String songId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _useLibrary();
      //If Album or Playlist is being played then Switch to original List of Songs
      if (ref.read(nowPlayingDetailsProvider).nowPlayingType !=
              NowPlayingType.songs ||
          ref.read(nowPlayingDetailsProvider).metadataList.isEmpty) {
        await setAudioSource(
          musicMetadataList: ref.read(filteredAudioFilesProvider).requireValue,
        );
      }

      //In case the same song is already playing
      if (songId ==
          ref.read(nowPlayingDetailsProvider).currentMetadata?.identity) {
        await _play();
        return;
      }

      final int index = ref
          .read(nowPlayingDetailsProvider)
          .metadataList
          .indexWhere((element) => element.identity == songId);
      if (index < 0) return;
      await ref.read(libraryAudioHandlerProvider).select(index);
    });
  }

  Future<void> togglePlayback() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (_spotifyActive) return _spotify.togglePlayback();
      final handler = ref.read(libraryAudioHandlerProvider);
      if (handler.recovering
          ? handler.wantsPlayback
          : ref.read(audioPlayerProvider).playing) {
        await pause();
      } else {
        await _play();
      }
    });
  }

  Future<void> seekForward() => seekToDuration(displayPosition.inSeconds + 1);

  Future<void> seekBackward() => seekToDuration(displayPosition.inSeconds - 1);

  Future<void> seekToDuration(int targetDurationInSeconds) async {
    state = await AsyncValue.guard(() async {
      final duration =
          ref
              .read(nowPlayingDetailsProvider)
              .currentMetadata
              ?.getTrackDuration ??
          0;
      final target = duration > 0
          ? targetDurationInSeconds.clamp(0, duration ~/ 1000)
          : targetDurationInSeconds.clamp(0, 1 << 31);
      if (_spotifyActive) {
        return _spotify.seekTo(Duration(seconds: target));
      }
      await ref
          .read(libraryAudioHandlerProvider)
          .seek(Duration(seconds: target));
    });
  }
}
