import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/widgets/display_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/music/playlist/providers/playlists_provider.dart';
import 'package:classipod/features/music/songs/screens/song_edit_screen.dart';
import 'package:classipod/features/now_playing/artist/artist_choice_screen.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/screen/ambient_now_playing_screen.dart';
import 'package:classipod/features/now_playing/video/music_video_link.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _NowPlayingMoreOptions {
  goToArtist,
  watchVideo,
  addToOnTheGo,
  editSong,
  ambientMode,
  sleepTimer,
  cancel;

  String title(BuildContext context) {
    switch (this) {
      case watchVideo:
        return context.localization.watchVideo;
      case addToOnTheGo:
        return context.localization.addToOnTheGoPlaylist;
      case goToArtist:
        return context.localization.goToArtist;
      case editSong:
        return context.localization.editSongOption;
      case ambientMode:
        return context.localization.ambientModeSettingTitle;
      case sleepTimer:
        return context.localization.sleepTimerTitle;
      case cancel:
        return context.localization.cancelText;
    }
  }
}

class NowPlayingMoreOptionsScreen extends ConsumerStatefulWidget {
  const NowPlayingMoreOptionsScreen({super.key});

  @override
  ConsumerState createState() => _NowPlayingMoreOptionsScreenState();
}

class _NowPlayingMoreOptionsScreenState
    extends ConsumerState<NowPlayingMoreOptionsScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.nowPlayingMoreOptions.name;

  /// Library actions (On-The-Go, browse, edit) only apply to local and
  /// Subsonic tracks; a Spotify track cannot join the local queue.
  @override
  List<_NowPlayingMoreOptions> get displayItems {
    final current = ref.watch(nowPlayingDetailsProvider).currentMetadata;
    return [
      for (final option in _NowPlayingMoreOptions.values)
        if (option == _NowPlayingMoreOptions.watchVideo
            ? musicVideoSearchUri(current) != null
            : !(current?.isSpotify ?? false) ||
                  option == _NowPlayingMoreOptions.goToArtist ||
                  option == _NowPlayingMoreOptions.ambientMode ||
                  option == _NowPlayingMoreOptions.sleepTimer ||
                  option == _NowPlayingMoreOptions.cancel)
          option,
    ];
  }

  @override
  Future<void> onSelectPressed() =>
      _navigateToScreen(displayItems[selectedDisplayItem]);

  @override
  void onMenuButtonPressed() => _closeScreen();

  void _closeScreen() {
    // Let every device-action listener see the options route before popping.
    // Otherwise Now Playing can handle the same Menu/Select press again.
    scheduleMicrotask(() {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        context.pop();
      }
    });
  }

  Future<void> _navigateToScreen(_NowPlayingMoreOptions optionItem) async {
    setState(() => selectedDisplayItem = displayItems.indexOf(optionItem));
    final currentSongMetadata = ref
        .read(nowPlayingDetailsProvider)
        .currentMetadata;
    switch (optionItem) {
      case _NowPlayingMoreOptions.watchVideo:
        final uri = musicVideoSearchUri(currentSongMetadata);
        if (uri == null) return;
        // The video brings its own sound; pause instead of mixing the two.
        await ref.read(audioPlayerServiceProvider.notifier).pause();
        await ref.read(musicVideoLauncherProvider)(uri);
        _closeScreen();
        break;
      case _NowPlayingMoreOptions.addToOnTheGo:
        ref
            .read(playlistsProvider.notifier)
            .addSongToPlaylist(currentSongMetadata);
        _closeScreen();
        break;
      case _NowPlayingMoreOptions.goToArtist:
        await Future<void>.value();
        if (!mounted) return;
        await goToArtist(context, ref);
        _closeScreen();
        break;
      case _NowPlayingMoreOptions.editSong:
        if (currentSongMetadata == null) {
          _closeScreen();
          return;
        }
        await showCupertinoDialog(
          context: context,
          builder: (dialogContext) =>
              SongEditScreen(songMetadata: currentSongMetadata),
        );
        if (mounted) {
          _closeScreen();
        }
        break;
      case _NowPlayingMoreOptions.ambientMode:
        await AmbientNowPlayingScreen.open(context);
        _closeScreen();
        break;
      case _NowPlayingMoreOptions.sleepTimer:
        await context.pushNamed(Routes.sleepTimer.name);
        break;
      case _NowPlayingMoreOptions.cancel:
        _closeScreen();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: CupertinoScrollbar(
        controller: scrollController,
        child: ListView.builder(
          controller: scrollController,
          itemCount: displayItems.length,
          prototypeItem: const DisplayListTile(text: '', isSelected: false),
          itemBuilder: (context, index) {
            return DisplayListTile(
              text: displayItems[index].title(context),
              isSelected: index == selectedDisplayItem,
              onTap: () async => _navigateToScreen(displayItems[index]),
            );
          },
        ),
      ),
    );
  }
}
