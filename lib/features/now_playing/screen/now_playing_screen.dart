import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/extensions/go_router_extensions.dart';
import 'package:classipod/core/lyrics/lyrics.dart';
import 'package:classipod/core/lyrics/lyrics_repository.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/models/playback_shuffle_mode.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/widgets/empty_state_widget.dart';
import 'package:classipod/core/widgets/subtle_reflection.dart';
import 'package:classipod/features/device/models/device_action.dart';
import 'package:classipod/features/device/services/device_buttons_service_provider.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/now_playing/artist/artist_choice_screen.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/screen/ambient_now_playing_screen.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_artwork_scene.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_bottom_bar.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_widget.dart';
import 'package:classipod/features/now_playing/widgets/rating_bar.dart';
import 'package:classipod/features/now_playing/widgets/scrubber_bar.dart';
import 'package:classipod/features/now_playing/widgets/shuffle_segmented_control.dart';
import 'package:classipod/features/now_playing/widgets/synced_lyrics_view.dart';
import 'package:classipod/features/now_playing/widgets/volume_bar.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/tutorial/controller/tutorial_controller.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:volume_controller/volume_controller.dart';

enum _NowPlayingBottomBarPage {
  seekBar,
  scrubberBar,
  volumeBar,
  ratingBar,
  shuffleBar,
  lyrics,
}

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final PageController _bottomBarPageController = PageController();
  final ScrollController _lyricsScrollController = ScrollController();
  final _scrubber = ScrubberController();
  Timer? _longPressTimer;
  Timer? _barInactivityTimer;
  Timer? _ambientTimer;
  PlaybackShuffleMode _shuffleMode = PlaybackShuffleMode.off;
  _NowPlayingBottomBarPage _bottomBarPage = _NowPlayingBottomBarPage.seekBar;
  String? _lastLyricsSongIndex;
  GlobalKey<SyncedLyricsViewState> _lyricsViewKey = GlobalKey();
  Future<void>? _progressReturnTransition;
  int? _progressReturnPage;
  int _activeInputs = 0;
  int _ratingAtOpen = 0;
  Future<double>? _volumeAtOpen;

  String get routeName => Routes.nowPlaying.name;

  /// Lyrics for the current track once loaded; instrumentals have none.
  Lyrics? _lyricsOf(MusicMetadata? track, {bool watch = false}) {
    if (track == null) return null;
    final value = watch
        ? ref.watch(lyricsProvider(track)).value
        : ref.read(lyricsProvider(track)).value;
    return value == null || value.isEmpty || value.instrumental ? null : value;
  }

  Future<void> onSelectPressed() async {
    final bool hasLyrics =
        _lyricsOf(ref.read(nowPlayingDetailsProvider).currentMetadata) != null;

    if (_bottomBarPage == _NowPlayingBottomBarPage.seekBar) {
      await _bottomBarPageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _bottomBarPage = _NowPlayingBottomBarPage.scrubberBar;
      });
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.scrubberBar) {
      final changed = await _scrubber.commit();
      if (!mounted) return;
      if (changed) {
        await returnToProgressBar();
        return;
      }
      await _bottomBarPageController.animateToPage(
        2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _ratingAtOpen =
            ref.read(nowPlayingDetailsProvider).currentMetadata?.rating ?? 0;
        _bottomBarPage = _NowPlayingBottomBarPage.ratingBar;
      });
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.ratingBar) {
      final rating =
          ref.read(nowPlayingDetailsProvider).currentMetadata?.rating ?? 0;
      if (rating != _ratingAtOpen) {
        await returnToProgressBar();
        return;
      }
      await _bottomBarPageController.animateToPage(
        3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _shuffleMode = ref.read(nowPlayingDetailsProvider).shuffleMode;
        _bottomBarPage = _NowPlayingBottomBarPage.shuffleBar;
      });
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.shuffleBar) {
      await ref
          .read(audioPlayerServiceProvider.notifier)
          .setShuffleMode(_shuffleMode);
      if (hasLyrics) {
        await _bottomBarPageController.animateToPage(
          4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
        );
        setState(() {
          _bottomBarPage = _NowPlayingBottomBarPage.lyrics;
        });
      } else {
        await _bottomBarPageController.animateToPage(
          4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
        );
        _bottomBarPageController.jumpToPage(0);
        setState(() {
          _bottomBarPage = _NowPlayingBottomBarPage.seekBar;
        });
      }
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.volumeBar) {
      final initial = await _volumeAtOpen;
      final current = await _readVolume();
      if (initial != null && (current - initial).abs() > 0.0001) {
        await returnToProgressBar();
      }
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.lyrics) {
      // Select leaves lyrics scrolling and returns to the sung line.
      _lyricsViewKey.currentState?.resumeFollowing();
      await _bottomBarPageController.animateToPage(
        5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      _bottomBarPageController.jumpToPage(0);
      setState(() {
        _bottomBarPage = _NowPlayingBottomBarPage.seekBar;
      });
    }
  }

  void onSelectLongPress() {
    unawaited(context.pushNamed(Routes.nowPlayingMoreOptions.name));
  }

  Future<void> scrollLyrics(double offsetChange) async {
    _lyricsViewKey.currentState?.pauseFollowing();
    if (!_lyricsScrollController.hasClients) {
      return;
    }

    final ScrollPosition position = _lyricsScrollController.position;
    final double targetOffset = (position.pixels + offsetChange).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (targetOffset == position.pixels) {
      return;
    }

    await _lyricsScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<double> _readVolume() async {
    if (ref.read(appVolumeActiveProvider)) {
      return ref.read(audioPlayerProvider).volume;
    }
    return VolumeController.instance.getVolume();
  }

  Future<void> _adjustVolume({required bool increase}) async {
    await (_volumeAtOpen ??= _readVolume());
    if (!mounted) return;
    final settings = ref.read(settingsPreferencesControllerProvider.notifier);
    await Future.wait([
      showVolumeBar(),
      increase ? settings.increaseVolume() : settings.decreaseVolume(),
    ]);
  }

  Future<void> showVolumeBar() async {
    await _progressReturnTransition;
    if (!mounted || _bottomBarPage == _NowPlayingBottomBarPage.volumeBar) {
      return;
    }
    setState(() {
      _bottomBarPage = _NowPlayingBottomBarPage.volumeBar;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_bottomBarPageController.hasClients) {
      return;
    }
    await _bottomBarPageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  Future<void> returnToProgressBar() async {
    if (!mounted || !_bottomBarPageController.hasClients) {
      return;
    }
    if (_bottomBarPage == _NowPlayingBottomBarPage.shuffleBar) {
      await ref
          .read(audioPlayerServiceProvider.notifier)
          .setShuffleMode(_shuffleMode);
      if (!mounted || !_bottomBarPageController.hasClients) {
        return;
      }
    }
    final nextPage = _bottomBarPageController.page!.round() + 1;
    setState(() {
      _progressReturnPage = nextPage;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_bottomBarPageController.hasClients) {
      return;
    }
    await _bottomBarPageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
    if (!mounted || !_bottomBarPageController.hasClients) {
      return;
    }
    _bottomBarPageController.jumpToPage(0);
    setState(() {
      _bottomBarPage = _NowPlayingBottomBarPage.seekBar;
      _progressReturnPage = null;
      _volumeAtOpen = null;
    });
    await WidgetsBinding.instance.endOfFrame;
  }

  /// With Ambient Mode on, 30 s without input while playing shows the
  /// ambient screen. One-shot and re-armed by input; never polls.
  void _restartAmbientTimer() {
    _ambientTimer?.cancel();
    _ambientTimer = null;
    if (!ref.read(settingsPreferencesControllerProvider).ambientMode) return;
    _ambientTimer = Timer(const Duration(seconds: 30), () async {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          ModalRoute.of(context)?.isCurrent != true ||
          !ref.read(nowPlayingDetailsProvider).isPlaying) {
        return;
      }
      await AmbientNowPlayingScreen.open(context);
      if (mounted) _restartAmbientTimer();
    });
  }

  void restartBarInactivityTimer() {
    _restartAmbientTimer();
    _barInactivityTimer?.cancel();
    if (!mounted ||
        _activeInputs > 0 ||
        _scrubber.isInteracting ||
        _progressReturnTransition != null ||
        _bottomBarPage == _NowPlayingBottomBarPage.seekBar ||
        _bottomBarPage == _NowPlayingBottomBarPage.lyrics) {
      return;
    }
    _barInactivityTimer = Timer(const Duration(seconds: 4), () {
      _progressReturnTransition = returnToProgressBar().whenComplete(() {
        _progressReturnTransition = null;
      });
    });
  }

  Future<void> handleUserInput(FutureOr<void> Function() action) async {
    _barInactivityTimer?.cancel();
    _activeInputs++;
    try {
      await _progressReturnTransition;
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          context.router.locationNamed == routeName) {
        await action();
      }
    } finally {
      _activeInputs--;
      restartBarInactivityTimer();
    }
  }

  Future<void> rotateForward() async {
    if (_bottomBarPage == _NowPlayingBottomBarPage.scrubberBar) {
      _scrubber.step(1);
      return;
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.shuffleBar) {
      setState(() {
        _shuffleMode =
            PlaybackShuffleMode.values[(_shuffleMode.index + 1).clamp(0, 2)];
      });
      return;
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.ratingBar) {
      await ref
          .read(nowPlayingDetailsProvider.notifier)
          .increaseCurrentMetadataRating();
      return;
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.lyrics) {
      await scrollLyrics(60);
      return;
    }
    await _adjustVolume(increase: true);
  }

  Future<void> rotateBackward() async {
    if (_bottomBarPage == _NowPlayingBottomBarPage.scrubberBar) {
      _scrubber.step(-1);
      return;
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.shuffleBar) {
      setState(() {
        _shuffleMode =
            PlaybackShuffleMode.values[(_shuffleMode.index - 1).clamp(0, 2)];
      });
      return;
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.ratingBar) {
      await ref
          .read(nowPlayingDetailsProvider.notifier)
          .decreaseCurrentMetadataRating();
      return;
    } else if (_bottomBarPage == _NowPlayingBottomBarPage.lyrics) {
      await scrollLyrics(-60);
      return;
    }
    await _adjustVolume(increase: false);
  }

  Future<void> seekForward() async {
    if (_bottomBarPage == _NowPlayingBottomBarPage.shuffleBar) {
      await rotateForward();
      return;
    }
    await ref.read(audioPlayerServiceProvider.notifier).nextSong();
  }

  Future<void> seekBackward() async {
    if (_bottomBarPage == _NowPlayingBottomBarPage.shuffleBar) {
      await rotateBackward();
      return;
    }
    await ref.read(audioPlayerServiceProvider.notifier).seekBackwards();
  }

  void seekForwardLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 50), (
      _,
    ) async {
      restartBarInactivityTimer();
      if (_bottomBarPage == _NowPlayingBottomBarPage.scrubberBar) {
        _scrubber.step(1);
        return;
      }
      await ref.read(audioPlayerServiceProvider.notifier).seekForward();
    });
  }

  void seekBackwardLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 50), (
      _,
    ) async {
      restartBarInactivityTimer();
      if (_bottomBarPage == _NowPlayingBottomBarPage.scrubberBar) {
        _scrubber.step(-1);
        return;
      }
      await ref.read(audioPlayerServiceProvider.notifier).seekBackward();
    });
  }

  void onLongPressEnd() {
    if (_longPressTimer?.isActive ?? false) {
      _longPressTimer?.cancel();
      ref.read(deviceButtonsServiceProvider.notifier).resetDeviceAction();
    }
  }

  void onMenuButtonPressed() {
    context.pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tutorialControllerProvider.notifier).playNowPlayingTutorial();
    });
    _restartAmbientTimer();
  }

  @override
  void dispose() {
    _ambientTimer?.cancel();
    _barInactivityTimer?.cancel();
    _longPressTimer?.cancel();
    _bottomBarPageController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  Future<void> deviceControlHandler(_, DeviceAction? newState) async {
    if (!mounted ||
        newState == null ||
        ModalRoute.of(context)?.isCurrent != true ||
        context.router.locationNamed != routeName) {
      return;
    }
    await handleUserInput(() async {
      switch (newState) {
        case DeviceAction.menu:
          onMenuButtonPressed();
          break;
        case DeviceAction.select:
          await onSelectPressed();
          break;
        case DeviceAction.selectLongPress:
          onSelectLongPress();
          break;
        case DeviceAction.rotateForward:
          await rotateForward();
          break;
        case DeviceAction.rotateBackward:
          await rotateBackward();
          break;
        case DeviceAction.seekForward:
          await seekForward();
          break;
        case DeviceAction.seekBackward:
          await seekBackward();
          break;
        case DeviceAction.seekForwardLongPress:
          seekForwardLongPress();
          break;
        case DeviceAction.seekBackwardLongPress:
          seekBackwardLongPress();
          break;
        case DeviceAction.playPause:
          break;
        case DeviceAction.longPressEnd:
          onLongPressEnd();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nowPlayingDetails = ref.watch(nowPlayingDetailsProvider);
    final lyrics = _lyricsOf(nowPlayingDetails.currentMetadata, watch: true);
    final bool hasLyrics = lyrics != null;
    final String? currentLyricsSongIndex =
        nowPlayingDetails.currentMetadata?.identity;

    if (_lastLyricsSongIndex != currentLyricsSongIndex) {
      _lastLyricsSongIndex = currentLyricsSongIndex;
      // A fresh key per track also keys the lyrics crossfade.
      _lyricsViewKey = GlobalKey<SyncedLyricsViewState>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_lyricsScrollController.hasClients) {
          return;
        }
        _lyricsScrollController.jumpTo(0);
      });
    }

    if (!hasLyrics &&
        _bottomBarPage == _NowPlayingBottomBarPage.lyrics &&
        _progressReturnTransition == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_bottomBarPageController.hasClients) {
          _bottomBarPageController.jumpToPage(0);
        }
        setState(() {
          _bottomBarPage = _NowPlayingBottomBarPage.seekBar;
        });
      });
    }

    ref.listen(deviceButtonsServiceProvider, deviceControlHandler);

    // A Spotify session resumed after a restart has a current track but no
    // listed queue; only a missing track means nothing is playing.
    if (nowPlayingDetails.currentMetadata == null) {
      return CupertinoPageScaffold(
        child: Column(
          children: [
            Expanded(
              child: EmptyStateWidget(
                emptyDescription: context.localization.noMusicFilesFound,
              ),
            ),
          ],
        ),
      );
    }

    final bottomBarPages = <Widget>[
      ...(_bottomBarPage == _NowPlayingBottomBarPage.volumeBar
          ? const [NowPlayingBottomBar(), VolumeBar(), NowPlayingBottomBar()]
          : [
              const NowPlayingBottomBar(),
              NowPlayingBottomBar(
                showScrubber: true,
                scrubberController: _scrubber,
                scrubberActive:
                    _bottomBarPage == _NowPlayingBottomBarPage.scrubberBar,
                onScrubChanged: () {
                  setState(() {});
                  restartBarInactivityTimer();
                },
              ),
              RatingBar(
                currentRating: nowPlayingDetails.currentMetadata?.rating ?? 0,
                onRatingClicked: (val) async {
                  await ref
                      .read(nowPlayingDetailsProvider.notifier)
                      .setCurrentMetadataRating(val ?? 0);
                },
              ),
              ShuffleSegmentedControl(
                shuffleMode: _shuffleMode,
                onValueChanged: (value) {
                  setState(() {
                    _shuffleMode = value ?? _shuffleMode;
                  });
                },
              ),
              // Lyrics mode keeps the progress bar in view.
              if (hasLyrics) const NowPlayingBottomBar(),
              const NowPlayingBottomBar(),
            ]),
    ];
    final returnPage = _progressReturnPage;
    if (returnPage != null) {
      while (bottomBarPages.length <= returnPage) {
        bottomBarPages.add(const NowPlayingBottomBar());
      }
      bottomBarPages[returnPage] = const NowPlayingBottomBar();
    }

    final lyricsState = nowPlayingDetails.currentMetadata == null
        ? null
        : ref.watch(lyricsProvider(nowPlayingDetails.currentMetadata!));
    final lyricsActive = _bottomBarPage == _NowPlayingBottomBarPage.lyrics;

    return Listener(
      onPointerDown: (_) => restartBarInactivityTimer(),
      onPointerMove: (_) => restartBarInactivityTimer(),
      onPointerUp: (_) => restartBarInactivityTimer(),
      onPointerSignal: (_) => restartBarInactivityTimer(),
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0xFF000000),
        child: NowPlayingArtworkScene(
          artworkPath: ref.watch(
            songAlbumArtworkProvider(nowPlayingDetails.currentMetadata),
          ),
          heroTag:
              "${nowPlayingDetails.currentMetadata?.albumName}-"
              "${nowPlayingDetails.currentMetadata?.albumArtistName}",
          onArtworkTap: () => unawaited(handleUserInput(onSelectPressed)),
          onArtworkLongPress: () =>
              unawaited(handleUserInput(onSelectLongPress)),
          panel: NowPlayingPanel(
            lyricsSynced: lyrics?.isSynced ?? false,
            lyricsActive: lyricsActive,
            // Lyrics never hold up playback: a failed lookup is simply
            // reported as unavailable.
            lyricsMessage: lyricsState?.isLoading ?? false
                ? context.localization.lyricsLoading
                : context.localization.lyricsUnavailable,
            lyrics: lyrics == null
                ? null
                : AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    child: SyncedLyricsView(
                      key: _lyricsViewKey,
                      lyrics: lyrics,
                      scrollController: _lyricsScrollController,
                      fontSize: 15,
                      currentColor: CupertinoColors.white,
                    ),
                  ),
            onLyricsLabelTap: () =>
                _lyricsViewKey.currentState?.resumeFollowing(),
            onGoToArtist: () => unawaited(goToArtist(context, ref)),
            bottomBar: SizedBox(
              height: 24 + SubtleReflection.visibleHeight,
              child: PageView(
                controller: _bottomBarPageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final page in bottomBarPages)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: SubtleReflection.visibleHeight,
                      ),
                      child: page,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
