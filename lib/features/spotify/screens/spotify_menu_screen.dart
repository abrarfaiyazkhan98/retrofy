import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/widgets/display_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/spotify/models/spotify_track_source.dart';
import 'package:classipod/features/spotify/providers/spotify_library_providers.dart';
import 'package:classipod/features/spotify/widgets/spotify_status_view.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Rows of the Spotify menu, shown in Music when Spotify is the source and
/// on the standalone Spotify screen.
enum SpotifyMenuItem {
  notConfigured,
  signIn,
  signingIn,
  error,
  playlists,
  albums,
  artists,
  likedSongs,
  recentlyPlayed,
  search,
  account,
  signOut,
}

/// The rows for the current sign-in state; empty while it is unknown.
List<SpotifyMenuItem> spotifyMenuItems(SpotifyAuthState? auth) =>
    switch (auth?.status) {
      null => const [],
      SpotifyAuthStatus.notConfigured => const [SpotifyMenuItem.notConfigured],
      SpotifyAuthStatus.signingIn => const [SpotifyMenuItem.signingIn],
      SpotifyAuthStatus.signedOut => [
        SpotifyMenuItem.signIn,
        if (auth?.error != null) SpotifyMenuItem.error,
      ],
      SpotifyAuthStatus.signedIn => const [
        SpotifyMenuItem.playlists,
        SpotifyMenuItem.albums,
        SpotifyMenuItem.artists,
        SpotifyMenuItem.likedSongs,
        SpotifyMenuItem.recentlyPlayed,
        SpotifyMenuItem.search,
        SpotifyMenuItem.account,
        SpotifyMenuItem.signOut,
      ],
    };

String spotifyMenuTitle(
  BuildContext context,
  SpotifyMenuItem item,
  SpotifyAuthState? auth,
) {
  final l10n = context.localization;
  return switch (item) {
    SpotifyMenuItem.notConfigured => l10n.spotifyNotConfigured,
    SpotifyMenuItem.signIn => l10n.spotifySignIn,
    SpotifyMenuItem.signingIn => l10n.spotifySigningIn,
    SpotifyMenuItem.error => spotifyErrorText(context, auth?.error),
    SpotifyMenuItem.playlists => l10n.playlistsScreenTitle,
    SpotifyMenuItem.albums => l10n.albumsScreenTitle,
    SpotifyMenuItem.artists => l10n.artistsScreenTitle,
    SpotifyMenuItem.likedSongs => l10n.spotifyLikedSongs,
    SpotifyMenuItem.recentlyPlayed => l10n.spotifyRecentlyPlayed,
    SpotifyMenuItem.search => l10n.searchScreenTitle,
    SpotifyMenuItem.account => l10n.spotifySignedInAs(
      auth?.profile?.displayName ?? '…',
    ),
    SpotifyMenuItem.signOut => l10n.spotifySignOut,
  };
}

/// Opens [item]'s screen or runs its action.
Future<void> openSpotifyMenuItem(
  BuildContext context,
  WidgetRef ref,
  SpotifyMenuItem item,
) async {
  final auth = ref.read(spotifyAuthControllerProvider.notifier);
  switch (item) {
    case SpotifyMenuItem.signIn:
    case SpotifyMenuItem.signingIn:
      await auth.signIn();
    case SpotifyMenuItem.signOut:
      await auth.signOut();
    case SpotifyMenuItem.playlists:
      await context.pushNamed(
        Routes.spotifyBrowse.name,
        extra: const SpotifyBrowseSource.playlists(),
      );
    case SpotifyMenuItem.albums:
      await context.pushNamed(
        Routes.spotifyBrowse.name,
        extra: const SpotifyBrowseSource.savedAlbums(),
      );
    case SpotifyMenuItem.artists:
      await context.pushNamed(
        Routes.spotifyBrowse.name,
        extra: const SpotifyBrowseSource.artists(),
      );
    case SpotifyMenuItem.likedSongs:
      final profile = ref.read(spotifyAuthControllerProvider).value?.profile;
      await context.pushNamed(
        Routes.spotifyTracks.name,
        extra: SpotifyTrackSource(
          title: context.localization.spotifyLikedSongs,
          tracks: spotifyLikedSongsProvider,
          // Liked Songs plays as the user's collection context when the
          // profile is known, so Next continues through the library.
          contextUri: profile == null
              ? null
              : 'spotify:user:${profile.id}:collection',
        ),
      );
    case SpotifyMenuItem.recentlyPlayed:
      await context.pushNamed(
        Routes.spotifyTracks.name,
        extra: SpotifyTrackSource(
          title: context.localization.spotifyRecentlyPlayed,
          tracks: spotifyRecentlyPlayedProvider,
        ),
      );
    case SpotifyMenuItem.search:
      await context.pushNamed(Routes.spotifySearch.name);
    case SpotifyMenuItem.notConfigured:
    case SpotifyMenuItem.error:
    case SpotifyMenuItem.account:
      break;
  }
}

class SpotifyMenuScreen extends ConsumerStatefulWidget {
  const SpotifyMenuScreen({super.key});

  @override
  ConsumerState createState() => _SpotifyMenuScreenState();
}

class _SpotifyMenuScreenState extends ConsumerState<SpotifyMenuScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.spotify.name;

  SpotifyAuthState? get _auth => ref.watch(spotifyAuthControllerProvider).value;

  @override
  List<SpotifyMenuItem> get displayItems => spotifyMenuItems(_auth);

  @override
  Future<void> onSelectPressed() async {
    final items = displayItems;
    if (items.isEmpty) return;
    await _select(items[selectedDisplayItem.clamp(0, items.length - 1)]);
  }

  Future<void> _select(SpotifyMenuItem item) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(item));
    await openSpotifyMenuItem(context, ref, item);
    if (item == SpotifyMenuItem.signOut && mounted) {
      setState(() => selectedDisplayItem = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = displayItems;
    if (items.isEmpty) return const SpotifyStatusView.loading();
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
                  text: spotifyMenuTitle(context, items[index], _auth),
                  isSelected: selected == index,
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
