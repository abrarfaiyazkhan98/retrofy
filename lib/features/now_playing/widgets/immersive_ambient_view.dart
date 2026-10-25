import 'dart:async';
import 'dart:math' as math;

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/lyrics/lyrics.dart';
import 'package:classipod/core/lyrics/lyrics_repository.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:classipod/core/widgets/artwork_glow.dart';
import 'package:classipod/core/widgets/artwork_image.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/widgets/synced_lyrics_view.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Ambient Mode with Artwork Glow on: the cover large and sharp, its colours
/// glowing across the screen, and a quiet player below. Tapping the cover
/// shows or hides the player; lyrics replace the cover with a small header.
class ImmersiveAmbientView extends ConsumerStatefulWidget {
  const ImmersiveAmbientView({super.key});

  @override
  ConsumerState<ImmersiveAmbientView> createState() =>
      _ImmersiveAmbientViewState();
}

class _ImmersiveAmbientViewState extends ConsumerState<ImmersiveAmbientView>
    with WidgetsBindingObserver {
  static const _artRadius = 14.0;
  static const _layout = Duration(milliseconds: 450);

  bool _controls = true;
  bool _lyrics = false;

  /// 0..1 while the progress bar is dragged.
  double? _scrub;
  ArtworkPalette _palette = ArtworkPalette.fallback;
  Object? _paletteKey;
  Timer? _clock;
  final _lyricsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  /// Elapsed time is redrawn once a second, only while visible.
  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _scrub == null) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      setState(() {});
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _lyricsScroll.dispose();
    super.dispose();
  }

  void _updatePalette(String? path, ImageProvider provider) {
    // Keyed like the Now Playing scene so both share cached palettes.
    final key = '$path|${provider.runtimeType}';
    if (key == _paletteKey) return;
    _paletteKey = key;
    unawaited(
      ArtworkPaletteCache.of(key, provider).then((palette) {
        if (mounted && _paletteKey == key) setState(() => _palette = palette);
      }),
    );
  }

  AudioPlayerServiceNotifier get _player =>
      ref.read(audioPlayerServiceProvider.notifier);

  /// Horizontal swipes on the cover change tracks; short or slow drags are
  /// ignored so a tap that wobbles never skips.
  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 700) return;
    unawaited(velocity < 0 ? _player.nextSong() : _player.seekBackwards());
  }

  Future<void> _cycleRepeat(LoopMode current) =>
      _player.setLoopMode(switch (current) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      });

  String _clockText(Duration value) {
    final seconds = value.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(nowPlayingDetailsProvider);
    final track = details.currentMetadata;
    final artworkPath = ref.watch(songAlbumArtworkProvider(track));
    final provider = artworkImage(ref, artworkPath);
    _updatePalette(artworkPath, provider);
    final Lyrics? lyrics = track == null
        ? null
        : ref.watch(lyricsProvider(track)).value;
    final showLyrics = _lyrics && lyrics != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final layout = reduceMotion ? Duration.zero : _layout;
    final padding = MediaQuery.paddingOf(context);
    final l10n = context.localization;

    return CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.dark),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: CupertinoColors.white,
          fontFamily: 'Helvetica',
          decoration: TextDecoration.none,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            const topBar = 56.0;
            final controlsHeight = math.min(260.0, height * 0.36);
            final side = math.min(width - 56, height * 0.46);
            final upper =
                height - padding.bottom - controlsHeight - padding.top - topBar;
            final artRect = showLyrics
                ? Rect.fromLTWH(24, padding.top + topBar, 56, 56)
                : Rect.fromLTWH(
                    (width - side) / 2,
                    padding.top + topBar + math.max(0, (upper - side) / 2),
                    side,
                    side,
                  );
            final cacheWidth = (side * MediaQuery.devicePixelRatioOf(context))
                .round();

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // A firm downward swipe anywhere closes Ambient Mode.
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 900) {
                  Navigator.of(context).pop();
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ArtworkGlow(
                      palette: _palette,
                      haloRect: showLyrics ? null : artRect,
                      haloRadius: _artRadius,
                      calm: showLyrics ? 1 : 0,
                    ),
                  ),
                  AnimatedPositioned.fromRect(
                    rect: artRect,
                    duration: layout,
                    curve: Curves.easeOutCubic,
                    child: GestureDetector(
                      onTap: () => setState(() => _controls = !_controls),
                      onHorizontalDragEnd: _onSwipe,
                      child: _Artwork(
                        provider: provider,
                        identity: artworkPath,
                        cacheWidth: cacheWidth,
                        radius: showLyrics ? 8 : _artRadius,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  ),
                  Positioned(
                    top: padding.top + 4,
                    left: 8,
                    right: 8,
                    child: Row(
                      children: [
                        _IconButton(
                          icon: CupertinoIcons.chevron_down,
                          label: l10n.ambientCloseLabel,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        if (lyrics != null)
                          _IconButton(
                            icon: showLyrics
                                ? CupertinoIcons.quote_bubble_fill
                                : CupertinoIcons.quote_bubble,
                            label: l10n.ambientLyricsLabel,
                            onPressed: () => setState(() => _lyrics = !_lyrics),
                          ),
                      ],
                    ),
                  ),
                  if (showLyrics) ...[
                    Positioned(
                      left: artRect.right + 14,
                      right: 24,
                      top: artRect.top,
                      height: artRect.height,
                      child: _TrackTitle(
                        title: track?.getTrackName ?? '',
                        artist: track?.getTrackArtistNames ?? '',
                        compact: true,
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 16,
                      top: artRect.bottom + 20,
                      bottom: padding.bottom + controlsHeight - 40,
                      child: ShaderMask(
                        // Lines fade out at the edges instead of being cut.
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0xFFFFFFFF),
                            Color(0xFFFFFFFF),
                            Color(0x00FFFFFF),
                          ],
                          stops: [0, 0.08, 0.85, 1],
                        ).createShader(rect),
                        blendMode: BlendMode.dstIn,
                        child: SyncedLyricsView(
                          lyrics: lyrics,
                          scrollController: _lyricsScroll,
                          fontSize: 27,
                          currentColor: CupertinoColors.white,
                          onLineTap: (time) =>
                              unawaited(_player.seekToDuration(time.inSeconds)),
                        ),
                      ),
                    ),
                  ],
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: padding.bottom + 12,
                    height: controlsHeight - 12,
                    child: IgnorePointer(
                      ignoring: !_controls && !showLyrics,
                      child: AnimatedOpacity(
                        opacity: _controls || showLyrics ? 1 : 0,
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 300),
                        child: _controlsPanel(
                          details.isPlaying,
                          details.isShuffleEnabled,
                          details.loopMode,
                          showLyrics: showLyrics,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _controlsPanel(
    bool playing,
    bool shuffling,
    LoopMode loopMode, {
    required bool showLyrics,
  }) {
    final details = ref.read(nowPlayingDetailsProvider);
    final track = details.currentMetadata;
    final total = Duration(milliseconds: track?.getTrackDuration ?? 0);
    final position = _scrub != null ? total * _scrub! : _player.displayPosition;
    final progress = total > Duration.zero
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = total - position;
    final favourite = (track?.rating ?? 0) >= 5;
    final dim = CupertinoColors.white.withValues(alpha: 0.6);
    final l10n = context.localization;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!showLyrics)
          Row(
            children: [
              Expanded(
                child: _TrackTitle(
                  title: track?.getTrackName ?? '',
                  artist: track?.getTrackArtistNames ?? '',
                ),
              ),
              if (track != null)
                _IconButton(
                  icon: favourite
                      ? CupertinoIcons.star_fill
                      : CupertinoIcons.star,
                  label: l10n.ambientFavouriteLabel,
                  onPressed: () => unawaited(
                    ref
                        .read(nowPlayingDetailsProvider.notifier)
                        .setCurrentMetadataRating(favourite ? 0 : 5),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            double fraction(Offset local) =>
                (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: total > Duration.zero
                  ? (d) => setState(() => _scrub = fraction(d.localPosition))
                  : null,
              onHorizontalDragUpdate: (d) =>
                  setState(() => _scrub = fraction(d.localPosition)),
              onHorizontalDragEnd: (_) {
                final target = total * (_scrub ?? 0);
                setState(() => _scrub = null);
                unawaited(_player.seekToDuration(target.inSeconds));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _ProgressTrack(
                  progress: progress,
                  active: _scrub != null,
                ),
              ),
            );
          },
        ),
        DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 12,
            color: dim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: Row(
            children: [
              Text(_clockText(position)),
              const Spacer(),
              Text(total > Duration.zero ? '-${_clockText(remaining)}' : ''),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _IconButton(
              icon: CupertinoIcons.shuffle,
              label: l10n.shuffleSettingTitle,
              size: 20,
              color: shuffling ? CupertinoColors.white : dim,
              onPressed: () => unawaited(_player.toggleShuffleMode()),
            ),
            _IconButton(
              icon: CupertinoIcons.backward_fill,
              label: l10n.ambientPreviousLabel,
              size: 30,
              onPressed: () => unawaited(_player.seekBackwards()),
            ),
            _IconButton(
              icon: playing
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              label: playing ? l10n.ambientPauseLabel : l10n.ambientPlayLabel,
              size: 44,
              onPressed: () => unawaited(_player.togglePlayback()),
            ),
            _IconButton(
              icon: CupertinoIcons.forward_fill,
              label: l10n.ambientNextLabel,
              size: 30,
              onPressed: () => unawaited(_player.nextSong()),
            ),
            _IconButton(
              icon: loopMode == LoopMode.one
                  ? CupertinoIcons.repeat_1
                  : CupertinoIcons.repeat,
              label: l10n.repeatModeSettingTitle,
              size: 20,
              color: loopMode == LoopMode.off ? dim : CupertinoColors.white,
              onPressed: () => unawaited(_cycleRepeat(loopMode)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The whole cover, always sharp and never cropped, crossfading between
/// tracks.
class _Artwork extends StatelessWidget {
  final ImageProvider provider;
  final String? identity;
  final int cacheWidth;
  final double radius;
  final bool reduceMotion;

  const _Artwork({
    required this.provider,
    required this.identity,
    required this.cacheWidth,
    required this.radius,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 600),
          child: Image(
            key: ValueKey(identity),
            image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                Image.asset(Assets.defaultAlbumCoverImage, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _TrackTitle extends StatelessWidget {
  final String title;
  final String artist;
  final bool compact;

  const _TrackTitle({
    required this.title,
    required this.artist,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400);
    return AnimatedSwitcher(
      duration: duration,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey('$title|$artist'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 16 : 22,
              fontWeight: FontWeight.w700,
              letterSpacing: compact ? 0 : -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 14 : 18,
              color: CupertinoColors.white.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  final double progress;
  final bool active;

  const _ProgressTrack({required this.progress, required this.active});

  @override
  Widget build(BuildContext context) {
    final height = active ? 8.0 : 5.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: height,
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(height),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.white.withValues(alpha: active ? 1 : 0.85),
            borderRadius: BorderRadius.circular(height),
          ),
        ),
      ),
    );
  }
}

/// Icon button with a 48 px touch target and a screen-reader label.
class _IconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double size;
  final Color color;

  const _IconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 22,
    this.color = CupertinoColors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        pressedOpacity: 0.5,
        onPressed: onPressed,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
