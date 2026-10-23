import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/extensions/go_router_extensions.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/widgets/album_art_song_list_tile.dart';
import 'package:classipod/core/widgets/artwork_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/spotify/models/spotify_track_source.dart';
import 'package:classipod/features/spotify/widgets/spotify_status_view.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rows above the tracks: a playback error if the last attempt failed, then
/// Play and Shuffle Play for albums and playlists. Those two also work for
/// playlists Spotify will not list and for accounts without Premium.
enum _Header { starting, error, play, shuffle }

class SpotifyTracksScreen extends ConsumerStatefulWidget {
  final SpotifyTrackSource source;

  const SpotifyTracksScreen({super.key, required this.source});

  @override
  ConsumerState createState() => _SpotifyTracksScreenState();
}

class _SpotifyTracksScreenState extends ConsumerState<SpotifyTracksScreen>
    with CustomScreen {
  Object? _playbackError;

  /// A play request is waiting for Spotify (connection or first approval).
  /// Further selections are ignored so only one play command is sent.
  bool _starting = false;

  @override
  String get routeName => Routes.spotifyTracks.name;

  @override
  double get displayTileHeight => ArtworkListTile.height;

  List<_Header> get _headers => [
    if (_starting) _Header.starting,
    if (_playbackError != null) _Header.error,
    if (widget.source.contextUri != null) ...[_Header.play, _Header.shuffle],
  ];

  @override
  int get extraDisplayItems => _headers.length;

  AsyncValue<List<MusicMetadata>> get _tracks =>
      ref.watch(widget.source.tracks);

  @override
  List<MusicMetadata> get displayItems => _tracks.value ?? const [];

  @override
  Future<void> onSelectPressed() => _select(selectedDisplayItem);

  Future<void> _select(int index) async {
    if (_starting) return;
    final headers = _headers;
    final header = index < headers.length ? headers[index] : null;
    if (header == _Header.error) return;
    final trackIndex = header == null ? index - headers.length : null;
    final source = widget.source;
    setState(() {
      _starting = true;
      _playbackError = null;
      // Keep the chosen row selected once the status row appears above it.
      final shown = _headers;
      selectedDisplayItem = header == null
          ? shown.length + trackIndex!
          : shown.indexOf(header);
    });
    try {
      await ref
          .read(audioPlayerServiceProvider.notifier)
          .playSpotify(
            tracks: displayItems,
            index: trackIndex,
            contextUri: source.contextUri,
            shuffle: header == null ? null : header == _Header.shuffle,
            nowPlayingType: source.nowPlayingType,
          );
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _playbackError = error;
          selectedDisplayItem = 0;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _starting = false;
      selectedDisplayItem = 0;
    });
    await context.openUniqueNamed(Routes.nowPlaying.name);
  }

  Widget _headerTile(_Header header, int index) {
    final l10n = context.localization;
    return ArtworkListTile(
      title: switch (header) {
        _Header.starting => l10n.spotifyConnecting,
        _Header.error => spotifyErrorText(context, _playbackError),
        _Header.play => l10n.spotifyPlay,
        _Header.shuffle => l10n.spotifyShufflePlay,
      },
      subtitle: header == _Header.error || header == _Header.starting
          ? null
          : widget.source.title,
      icon: switch (header) {
        _Header.starting => CupertinoIcons.hourglass,
        _Header.error => CupertinoIcons.exclamationmark_triangle,
        _Header.play => CupertinoIcons.play_arrow_solid,
        _Header.shuffle => CupertinoIcons.shuffle,
      },
      isSelected: selectedDisplayItem == index,
      onTap: () => unawaited(_select(index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final headers = _headers;
    final items = tracks.value ?? const <MusicMetadata>[];
    // Without Play rows there is nothing to show until the tracks load.
    if (widget.source.contextUri == null && items.isEmpty) {
      if (tracks.hasError) return SpotifyStatusView.error(tracks.error);
      if (tracks.isLoading) return const SpotifyStatusView.loading();
      return SpotifyStatusView.message(context.localization.noMusicFilesFound);
    }
    // Loading or failure below the Play rows, which stay usable either way.
    final Widget? footer = items.isNotEmpty
        ? null
        : tracks.hasError
        ? ArtworkListTile(
            title: spotifyErrorText(context, tracks.error),
            icon: CupertinoIcons.info,
            isSelected: false,
            onTap: () {},
          )
        : tracks.isLoading
        ? const Center(child: CupertinoActivityIndicator())
        : null;
    final playingId = ref
        .watch(nowPlayingDetailsProvider.select((e) => e.currentMetadata))
        ?.identity;
    final count = headers.length + items.length + (footer == null ? 0 : 1);
    return CupertinoPageScaffold(
      child: Column(
        children: [
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                itemCount: count,
                itemExtent: ArtworkListTile.height,
                itemBuilder: (context, index) {
                  if (index < headers.length) {
                    return _headerTile(headers[index], index);
                  }
                  final trackIndex = index - headers.length;
                  if (trackIndex >= items.length) return footer!;
                  final track = items[trackIndex];
                  return AlbumArtSongListTile(
                    songMetadata: track,
                    isSelected: selectedDisplayItem == index,
                    isCurrentlyPlaying: playingId == track.identity,
                    onTap: () => unawaited(_select(index)),
                    onLongPress: () {},
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
