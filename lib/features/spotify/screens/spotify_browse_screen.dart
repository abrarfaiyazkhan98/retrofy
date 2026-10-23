import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:classipod/core/widgets/artwork_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/spotify/models/spotify_track_source.dart';
import 'package:classipod/features/spotify/providers/spotify_library_providers.dart';
import 'package:classipod/features/spotify/widgets/spotify_status_view.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the track list for a Spotify album.
Future<void> openSpotifyAlbum(BuildContext context, SpotifyAlbum album) =>
    context.pushNamed(
      Routes.spotifyTracks.name,
      extra: SpotifyTrackSource(
        title: album.name,
        tracks: spotifyAlbumTracksProvider(album),
        contextUri: album.uri,
        nowPlayingType: NowPlayingType.album,
      ),
    );

/// Opens the album list for a Spotify artist.
Future<void> openSpotifyArtist(BuildContext context, SpotifyArtist artist) =>
    context.pushNamed(
      Routes.spotifyBrowse.name,
      extra: SpotifyBrowseSource.artistAlbums(artist),
    );

class _BrowseRow {
  final String title;
  final String? subtitle;
  final String? artworkPath;
  final IconData? icon;
  final Future<void> Function(BuildContext) open;

  const _BrowseRow({
    required this.title,
    required this.open,
    this.subtitle,
    this.artworkPath,
    this.icon,
  });
}

class SpotifyBrowseScreen extends ConsumerStatefulWidget {
  final SpotifyBrowseSource source;

  const SpotifyBrowseScreen({super.key, required this.source});

  @override
  ConsumerState createState() => _SpotifyBrowseScreenState();
}

class _SpotifyBrowseScreenState extends ConsumerState<SpotifyBrowseScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.spotifyBrowse.name;

  @override
  double get displayTileHeight => ArtworkListTile.height;

  AsyncValue<List<_BrowseRow>> get _rows {
    final source = widget.source;
    final artist = source.artist;
    if (source.isPlaylists) {
      final userId = ref
          .watch(
            spotifyAuthControllerProvider.select(
              (value) => value.value?.profile,
            ),
          )
          ?.id;
      return ref
          .watch(spotifyPlaylistsProvider)
          .whenData(
            (playlists) => [
              for (final playlist in playlists)
                _BrowseRow(
                  title: playlist.name,
                  artworkPath: playlist.imageUrl,
                  open: (context) => context.pushNamed(
                    Routes.spotifyTracks.name,
                    extra: SpotifyTrackSource(
                      title: playlist.name,
                      // Without the owner check the request would only fail;
                      // the playlist still plays as a whole.
                      tracks: userId == null || playlist.canListItems(userId)
                          ? spotifyPlaylistTracksProvider(playlist.id)
                          : spotifyNoTracksProvider,
                      contextUri: playlist.uri,
                      nowPlayingType: NowPlayingType.playlist,
                    ),
                  ),
                ),
            ],
          );
    }
    if (source.isArtists) {
      return ref
          .watch(spotifyFollowedArtistsProvider)
          .whenData(
            (artists) => [
              for (final artist in artists)
                _BrowseRow(
                  title: artist.name,
                  artworkPath: artist.imageUrl,
                  icon: artist.imageUrl == null
                      ? CupertinoIcons.person_alt
                      : null,
                  open: (context) => openSpotifyArtist(context, artist),
                ),
            ],
          );
    }
    final albums = artist == null
        ? ref.watch(spotifySavedAlbumsProvider)
        : ref.watch(spotifyArtistAlbumsProvider(artist.id));
    return albums.whenData(
      (albums) => [
        for (final album in albums)
          _BrowseRow(
            title: album.name,
            subtitle: [
              if (artist == null) album.artistLine,
              if (album.year != null) '${album.year}',
            ].join(' · '),
            artworkPath: album.imageUrl,
            open: (context) => openSpotifyAlbum(context, album),
          ),
      ],
    );
  }

  @override
  List<_BrowseRow> get displayItems => _rows.value ?? const [];

  @override
  Future<void> onSelectPressed() => _open(selectedDisplayItem);

  Future<void> _open(int index) async {
    final rows = displayItems;
    if (index < 0 || index >= rows.length) return;
    setState(() => selectedDisplayItem = index);
    await rows[index].open(context);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.hasError && !rows.hasValue) {
      return SpotifyStatusView.error(rows.error);
    }
    final items = rows.value;
    if (items == null) return const SpotifyStatusView.loading();
    if (items.isEmpty) {
      return SpotifyStatusView.message(
        widget.source.isPlaylists || widget.source.isArtists
            ? context.localization.noMusicFilesFound
            : context.localization.noAlbumsFound,
      );
    }
    return CupertinoPageScaffold(
      child: Column(
        children: [
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                itemCount: items.length,
                itemExtent: ArtworkListTile.height,
                itemBuilder: (context, index) => ArtworkListTile(
                  title: items[index].title,
                  subtitle: items[index].subtitle,
                  artworkPath: items[index].artworkPath,
                  icon: items[index].icon,
                  isSelected: selectedDisplayItem == index,
                  onTap: () => unawaited(_open(index)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
