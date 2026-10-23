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

enum _SpotifyMenuItem {
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
  List<_SpotifyMenuItem> get displayItems {
    final auth = _auth;
    return switch (auth?.status) {
      null => const [],
      SpotifyAuthStatus.notConfigured => const [_SpotifyMenuItem.notConfigured],
      SpotifyAuthStatus.signingIn => const [_SpotifyMenuItem.signingIn],
      SpotifyAuthStatus.signedOut => [
        _SpotifyMenuItem.signIn,
        if (auth?.error != null) _SpotifyMenuItem.error,
      ],
      SpotifyAuthStatus.signedIn => const [
        _SpotifyMenuItem.playlists,
        _SpotifyMenuItem.albums,
        _SpotifyMenuItem.artists,
        _SpotifyMenuItem.likedSongs,
        _SpotifyMenuItem.recentlyPlayed,
        _SpotifyMenuItem.search,
        _SpotifyMenuItem.account,
        _SpotifyMenuItem.signOut,
      ],
    };
  }

  String _title(_SpotifyMenuItem item) {
    final l10n = context.localization;
    return switch (item) {
      _SpotifyMenuItem.notConfigured => l10n.spotifyNotConfigured,
      _SpotifyMenuItem.signIn => l10n.spotifySignIn,
      _SpotifyMenuItem.signingIn => l10n.spotifySigningIn,
      _SpotifyMenuItem.error => spotifyErrorText(context, _auth?.error),
      _SpotifyMenuItem.playlists => l10n.playlistsScreenTitle,
      _SpotifyMenuItem.albums => l10n.albumsScreenTitle,
      _SpotifyMenuItem.artists => l10n.artistsScreenTitle,
      _SpotifyMenuItem.likedSongs => l10n.spotifyLikedSongs,
      _SpotifyMenuItem.recentlyPlayed => l10n.spotifyRecentlyPlayed,
      _SpotifyMenuItem.search => l10n.searchScreenTitle,
      _SpotifyMenuItem.account => l10n.spotifySignedInAs(
        _auth?.profile?.displayName ?? '…',
      ),
      _SpotifyMenuItem.signOut => l10n.spotifySignOut,
    };
  }

  @override
  Future<void> onSelectPressed() async {
    final items = displayItems;
    if (items.isEmpty) return;
    await _select(items[selectedDisplayItem.clamp(0, items.length - 1)]);
  }

  Future<void> _select(_SpotifyMenuItem item) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(item));
    final auth = ref.read(spotifyAuthControllerProvider.notifier);
    switch (item) {
      case _SpotifyMenuItem.signIn:
      case _SpotifyMenuItem.signingIn:
        await auth.signIn();
      case _SpotifyMenuItem.signOut:
        await auth.signOut();
        if (mounted) setState(() => selectedDisplayItem = 0);
      case _SpotifyMenuItem.playlists:
        await context.pushNamed(
          Routes.spotifyBrowse.name,
          extra: const SpotifyBrowseSource.playlists(),
        );
      case _SpotifyMenuItem.albums:
        await context.pushNamed(
          Routes.spotifyBrowse.name,
          extra: const SpotifyBrowseSource.savedAlbums(),
        );
      case _SpotifyMenuItem.artists:
        await context.pushNamed(
          Routes.spotifyBrowse.name,
          extra: const SpotifyBrowseSource.artists(),
        );
      case _SpotifyMenuItem.likedSongs:
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
      case _SpotifyMenuItem.recentlyPlayed:
        await context.pushNamed(
          Routes.spotifyTracks.name,
          extra: SpotifyTrackSource(
            title: context.localization.spotifyRecentlyPlayed,
            tracks: spotifyRecentlyPlayedProvider,
          ),
        );
      case _SpotifyMenuItem.search:
        await context.pushNamed(Routes.spotifySearch.name);
      case _SpotifyMenuItem.notConfigured:
      case _SpotifyMenuItem.error:
      case _SpotifyMenuItem.account:
        break;
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
                  text: _title(items[index]),
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
