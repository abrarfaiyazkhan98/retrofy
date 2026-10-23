import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/models/playback_shuffle_mode.dart';
import 'package:classipod/core/providers/filtered_audio_files_provider.dart';
import 'package:classipod/core/repositories/library/library_repository.dart';
import 'package:classipod/core/services/audio_files_service.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/services/playback/playback_backend.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:classipod/core/spotify/spotify_playback_controller.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/core/subsonic/subsonic_controller.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/music/playlist/providers/playlists_provider.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

final nowPlayingDetailsProvider =
    NotifierProvider<NowPlayingDetailsNotifier, NowPlayingModel>(
      NowPlayingDetailsNotifier.new,
    );

class NowPlayingDetailsNotifier extends Notifier<NowPlayingModel> {
  bool get _spotifyActive =>
      ref.read(playbackBackendProvider) == PlaybackBackend.spotify;

  @override
  NowPlayingModel build() {
    final player = ref.read(audioPlayerProvider);
    final handler = ref.read(libraryAudioHandlerProvider);
    final subscriptions = <StreamSubscription<dynamic>>[];
    ref.listen(
      spotifyPlaybackControllerProvider.select((value) => value.player),
      (_, player) {
        if (player != null && _spotifyActive) _applySpotify(player);
      },
    );
    subscriptions.add(
      handler.indexStream.listen((newIndex) {
        if (_spotifyActive) return;
        if (newIndex != null &&
            newIndex != state.currentIndex &&
            newIndex < state.metadataList.length) {
          state = state.copyWith(
            currentIndex: newIndex,
            queuePosition: handler.logicalQueue.position,
            currentMetadata: state.metadataList[newIndex],
          );
        }
      }),
    );

    subscriptions.add(
      player.playingStream.listen((isPlaying) {
        if (_spotifyActive) return;
        if (isPlaying != state.isPlaying) {
          state = state.copyWith(isPlaying: isPlaying);
        }
      }),
    );

    final loopStream = handler.playbackState
        .map(
          (value) => switch (value.repeatMode) {
            AudioServiceRepeatMode.one => LoopMode.one,
            AudioServiceRepeatMode.all ||
            AudioServiceRepeatMode.group => LoopMode.all,
            AudioServiceRepeatMode.none => LoopMode.off,
          },
        )
        .distinct();
    subscriptions.add(
      loopStream.listen((loopMode) {
        if (_spotifyActive) return;
        if (loopMode != state.loopMode) {
          state = state.copyWith(loopMode: loopMode);
        }
      }),
    );

    final queueOrderStream = handler.playbackState
        .map(
          (value) => (
            shuffleMode: PlaybackShuffleMode.fromAudioService(
              value.shuffleMode,
            ),
            position: handler.logicalQueue.position,
          ),
        )
        .distinct();
    subscriptions.add(
      queueOrderStream.listen((order) {
        if (_spotifyActive) return;
        state = state.copyWith(
          shuffleMode: order.shuffleMode,
          queuePosition: order.position,
        );
      }),
    );
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    });

    return NowPlayingModel(
      currentIndex: 0,
      isPlaying: false,
      nowPlayingType: NowPlayingType.songs,
      metadataList: [],
      loopMode: LoopMode.off,
      shuffleMode: PlaybackShuffleMode.off,
    );
  }

  void setSpotifyQueue({
    required NowPlayingType nowPlayingType,
    required List<MusicMetadata> tracks,
    int? index,
  }) {
    // Without an index the Spotify player state identifies the track.
    state = NowPlayingModel(
      currentIndex: index ?? 0,
      isPlaying: true,
      nowPlayingType: nowPlayingType,
      currentMetadata: index == null ? null : tracks[index],
      metadataList: tracks,
      shuffleMode: state.shuffleMode,
      loopMode: state.loopMode,
    );
    final player = ref.read(spotifyPlaybackControllerProvider).player;
    if (player != null) _applySpotify(player);
  }

  /// Mirrors what the Spotify app reports, including track changes made in
  /// Spotify itself or when it continues past the listed tracks.
  void _applySpotify(SpotifyPlayerState player) {
    var index = state.currentIndex;
    var current = state.currentMetadata;
    final uri = player.trackUri;
    if (uri != null && current?.songId != uri) {
      final list = state.metadataList;
      // Prefer the next occurrence so repeated tracks advance naturally.
      var found = -1;
      for (var offset = 0; offset < list.length && found < 0; offset++) {
        final candidate = (index + offset) % list.length;
        if (list[candidate].songId == uri) found = candidate;
      }
      if (found >= 0) {
        index = found;
        current = list[found];
      } else {
        current = MusicMetadata(
          songId: uri,
          trackName: player.trackName,
          trackArtistNames: player.artists.isEmpty ? null : player.artists,
          albumName: player.albumName,
          trackDuration: player.durationMs,
          thumbnailPath: spotifyImageUriToUrl(player.imageUri),
          isOnDevice: false,
        );
      }
    }
    state = NowPlayingModel(
      currentIndex: index,
      queuePosition: index,
      isPlaying: !player.isPaused,
      nowPlayingType: state.nowPlayingType,
      currentMetadata: current,
      metadataList: state.metadataList,
      shuffleMode: player.isShuffling
          ? PlaybackShuffleMode.songs
          : PlaybackShuffleMode.off,
      loopMode: switch (player.repeatMode) {
        SpotifyPlayerState.repeatOne => LoopMode.one,
        SpotifyPlayerState.repeatAll => LoopMode.all,
        _ => LoopMode.off,
      },
    );
  }

  void reconcileMetadata(List<MusicMetadata> songs) {
    final index = songs.indexWhere(
      (song) => song.identity == state.currentMetadata?.identity,
    );
    state = NowPlayingModel(
      metadataList: songs,
      currentIndex: index < 0 ? 0 : index,
      queuePosition: ref
          .read(libraryAudioHandlerProvider)
          .logicalQueue
          .position,
      currentMetadata: songs.isEmpty ? null : songs[index < 0 ? 0 : index],
      isPlaying: index >= 0 && state.isPlaying,
      shuffleMode: state.shuffleMode,
      loopMode: state.loopMode,
      nowPlayingType: state.nowPlayingType,
    );
  }

  void setNewMetadataList({
    NowPlayingType? nowPlayingType,
    required List<MusicMetadata> newMetadataList,
  }) {
    state = NowPlayingModel(
      isPlaying: state.isPlaying,
      shuffleMode: state.shuffleMode,
      loopMode: state.loopMode,
      currentIndex: 0,
      nowPlayingType: nowPlayingType ?? state.nowPlayingType,
      currentMetadata: newMetadataList.isNotEmpty ? newMetadataList[0] : null,
      metadataList: newMetadataList,
    );
  }

  Future<void> setCurrentMetadataRating(int val) async {
    if (0 <= val && val <= 5 && state.currentMetadata != null) {
      final newMetadata = state.currentMetadata!.copyWith(rating: val);
      await updateMetadata(newMetadata);
    }
  }

  Future<void> increaseCurrentMetadataRating() async {
    final int? currentRating = state.currentMetadata?.rating;
    if (currentRating != null && currentRating < 5) {
      await setCurrentMetadataRating(currentRating + 1);
    }
  }

  Future<void> decreaseCurrentMetadataRating() async {
    final int? currentRating = state.currentMetadata?.rating;
    if (currentRating != null && currentRating > 0) {
      await setCurrentMetadataRating(currentRating - 1);
    }
  }

  Future<void> updateMetadata(MusicMetadata updatedMetadata) async {
    state = state.copyWith(
      currentMetadata:
          state.currentMetadata?.identity == updatedMetadata.identity
          ? updatedMetadata
          : state.currentMetadata,
      metadataList: [
        for (final metadata in state.metadataList)
          if (metadata.identity == updatedMetadata.identity)
            updatedMetadata
          else
            metadata,
      ],
    );

    // Spotify ratings are kept for this session only.
    if (updatedMetadata.isSpotify) return;
    if (updatedMetadata.isSubsonic) {
      await ref
          .read(subsonicControllerProvider.notifier)
          .updateSong(updatedMetadata);
    } else if (updatedMetadata.songId != null) {
      await LibraryRepository.updateRating(updatedMetadata);
      ref
          .read(audioFilesServiceProvider.notifier)
          .replaceMetadata(updatedMetadata);
    }
    ref.invalidate(filteredAudioFilesProvider);
    ref.invalidate(albumDetailsProvider);
    ref.invalidate(playlistsProvider);
  }
}
