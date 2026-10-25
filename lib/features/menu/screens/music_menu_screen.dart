import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/widgets/display_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/menu/providers/music_source_provider.dart';
import 'package:classipod/features/spotify/screens/spotify_menu_screen.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _MusicListDisplayItems {
  coverFlow,
  playlists,
  artists,
  albums,
  songs,
  genres,
  search;

  String title(BuildContext context) {
    switch (this) {
      case coverFlow:
        return context.localization.coverFlowScreenTitle;
      case playlists:
        return context.localization.playlistsScreenTitle;
      case artists:
        return context.localization.artistsScreenTitle;
      case albums:
        return context.localization.albumsScreenTitle;
      case songs:
        return context.localization.songsScreenTitle;
      case genres:
        return context.localization.genresScreenTitle;
      case search:
        return context.localization.searchScreenTitle;
    }
  }
}

/// Music lists two source rows, Library and Spotify, with a checkmark on
/// the active one, followed by that source's menu. The wheel reaches both
/// sources without another menu level, and the choice is remembered.
class MusicMenuScreen extends ConsumerStatefulWidget {
  const MusicMenuScreen({super.key});

  @override
  ConsumerState createState() => _MusicMenuScreenState();
}

class _MusicMenuScreenState extends ConsumerState<MusicMenuScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.musicMenu.name;

  SpotifyAuthState? get _auth => ref.watch(spotifyAuthControllerProvider).value;

  /// [MusicSource] rows, then [_MusicListDisplayItems] for the library or
  /// [SpotifyMenuItem]s for Spotify.
  @override
  List<Object> get displayItems => [
    ...MusicSource.values,
    ...switch (ref.watch(musicSourceProvider)) {
      MusicSource.library => _MusicListDisplayItems.values,
      MusicSource.spotify => spotifyMenuItems(_auth),
    },
  ];

  @override
  void initState() {
    super.initState();
    // Start on the source's first entry rather than the source rows.
    selectedDisplayItem = MusicSource.values.length;
  }

  @override
  Future<void> onSelectPressed() async {
    final items = displayItems;
    await _select(items[selectedDisplayItem.clamp(0, items.length - 1)]);
  }

  Future<void> _select(Object item) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(item));
    switch (item) {
      case final MusicSource source:
        await ref.read(musicSourceProvider.notifier).choose(source);
      case final SpotifyMenuItem spotifyItem:
        await openSpotifyMenuItem(context, ref, spotifyItem);
        if (spotifyItem == SpotifyMenuItem.signOut && mounted) {
          setState(() => selectedDisplayItem = MusicSource.values.length);
        }
      case final _MusicListDisplayItems libraryItem:
        await _navigateToScreen(libraryItem);
    }
  }

  String _title(Object item) => switch (item) {
    MusicSource.library => context.localization.musicSourceLibrary,
    MusicSource.spotify => context.localization.spotifyTitle,
    final SpotifyMenuItem spotifyItem => spotifyMenuTitle(
      context,
      spotifyItem,
      _auth,
    ),
    final _MusicListDisplayItems libraryItem => libraryItem.title(context),
    _ => '',
  };

  Future<void> _navigateToScreen(
    _MusicListDisplayItems musicDisplayItem,
  ) async {
    switch (musicDisplayItem) {
      case _MusicListDisplayItems.coverFlow:
        unawaited(ref.read(splitScreenViewControllerProvider).closeSplitView());
        await context.pushNamed(
          Routes.coverFlow.name,
          extra: Routes.musicMenu.name,
        );
        unawaited(ref.read(splitScreenViewControllerProvider).openSplitView());
        break;
      case _MusicListDisplayItems.playlists:
        context.goNamed(Routes.playlists.name);
        break;
      case _MusicListDisplayItems.artists:
        context.goNamed(Routes.artists.name);
        break;
      case _MusicListDisplayItems.albums:
        context.goNamed(Routes.albums.name);
        break;
      case _MusicListDisplayItems.songs:
        context.goNamed(Routes.songs.name);
        break;
      case _MusicListDisplayItems.genres:
        context.goNamed(Routes.genres.name);
        break;
      case _MusicListDisplayItems.search:
        context.goNamed(Routes.search.name);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = displayItems;
    final source = ref.watch(musicSourceProvider);
    final selected = selectedDisplayItem.clamp(0, items.length - 1);
    return CupertinoPageScaffold(
      child: Column(
        children: [
          Flexible(
            child: CupertinoScrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                itemCount: items.length,
                prototypeItem: const DisplayListTile(
                  text: '',
                  isSelected: false,
                ),
                itemBuilder: (context, index) => DisplayListTile(
                  text: _title(items[index]),
                  isSelected: selected == index,
                  isChecked: items[index] == source,
                  onTap: () => unawaited(_select(items[index])),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
