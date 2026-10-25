import 'dart:async';
import 'dart:math' as math;

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:classipod/core/widgets/artwork_image.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_widget.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Carries the current artwork's palette to progress bars and lyrics so they
/// pick up the cover's colour without extra parameters.
class ArtworkAccent extends InheritedWidget {
  final ArtworkPalette palette;

  const ArtworkAccent({super.key, required this.palette, required super.child});

  static ArtworkPalette? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArtworkAccent>()?.palette;

  /// Progress fill in the accent colour, shaded like the classic bar.
  static LinearGradient progressOf(ArtworkPalette palette) {
    final hsl = HSLColor.fromColor(palette.accent);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        hsl.withLightness((hsl.lightness + 0.18).clamp(0, 1)).toColor(),
        palette.accent,
        hsl.withLightness((hsl.lightness - 0.12).clamp(0, 1)).toColor(),
      ],
    );
  }

  @override
  bool updateShouldNotify(ArtworkAccent oldWidget) =>
      oldWidget.palette != palette;
}

/// Where the cover, the title and the information panel go in a display of
/// a given size. Pure geometry, so every window shape can be tested.
///
/// Portrait displays put a compact cover beside the title so the lyrics get
/// most of the height; landscape displays give the cover a column of its
/// own; very narrow displays stack the cover above the title.
@immutable
class NowPlayingGeometry {
  /// Side of the square cover; 0 hides it.
  final double artworkSize;

  /// Cover in a column of its own beside everything else (wide, short
  /// windows).
  final bool sideBySide;

  /// Title, artist and album to the right of the cover (portrait).
  final bool titleBesideArtwork;

  /// Title and artist only, with the album folded into the artist line.
  final bool compactMetadata;

  /// Height left for the lyrics surface; under
  /// [NowPlayingPanel.minLyricsHeight] the lyrics are left out.
  final double lyricsHeight;

  const NowPlayingGeometry({
    required this.artworkSize,
    required this.sideBySide,
    this.titleBesideArtwork = false,
    this.compactMetadata = false,
    this.lyricsHeight = 0,
  });

  /// Margin around the content and between its blocks.
  static const inset = 14.0;
  static const topInset = 12.0;

  /// Progress bar and Go to Artist, with the gap above them.
  static const controlsHeight = 84.0;

  /// Title, artist and album lines; compact drops the album line.
  static const metadataHeight = 64.0;
  static const compactMetadataHeight = 46.0;

  /// Below this height the metadata is compact.
  static const compactBelow = 300.0;

  /// Height the panel needs for the title, artist, progress bar and the
  /// Go to Artist row, without lyrics.
  static const panelMinHeight = topInset + metadataHeight + controlsHeight;

  /// Width the panel needs for the progress row and Go to Artist.
  static const panelMinWidth = 240.0;

  /// Width the title needs beside the cover.
  static const metadataMinWidth = 140.0;

  /// Narrower displays stack the cover above the title.
  static const besideMinWidth = 280.0;

  /// The cover is dropped below this size rather than shown as a stamp.
  static const minArtwork = 56.0;

  /// Tablets and desktop windows never blow the cover up past this.
  static const maxArtwork = 260.0;

  /// Height above the lyrics surface: the cover and the metadata.
  double get headerHeight {
    final meta = compactMetadata ? compactMetadataHeight : metadataHeight;
    if (sideBySide) return meta;
    if (titleBesideArtwork) return math.max(artworkSize, meta);
    return artworkSize == 0 ? meta : artworkSize + inset + meta;
  }

  factory NowPlayingGeometry.of(Size size) {
    final width = size.width;
    final height = size.height;
    final compact = height < compactBelow;
    final meta = compact ? compactMetadataHeight : metadataHeight;
    double fit(double side) => side < minArtwork ? 0 : side;

    if (width >= height * 1.25 && width >= 320) {
      // Landscape-like windows: the cover fills its column on the left and
      // the right column keeps at least its minimum width.
      final side = fit(
        [
          height - 2 * topInset,
          width * 0.36,
          width - panelMinWidth - 3 * inset,
          maxArtwork,
        ].reduce(math.min),
      );
      return NowPlayingGeometry(
        artworkSize: side,
        sideBySide: true,
        compactMetadata: compact,
        lyricsHeight: height - topInset - meta - inset - controlsHeight,
      );
    }
    if (width >= besideMinWidth) {
      // Portrait: a compact cover beside the title, sized so the lyrics
      // keep about half the display.
      final side = fit(
        [
          width * 0.58,
          width - metadataMinWidth - 3 * inset,
          height * 0.36,
          height - controlsHeight - 3 * inset,
          maxArtwork,
        ].reduce(math.min),
      );
      final header = math.max(side, meta);
      return NowPlayingGeometry(
        artworkSize: side,
        sideBySide: false,
        titleBesideArtwork: true,
        compactMetadata: compact,
        lyricsHeight: height - topInset - header - inset - controlsHeight,
      );
    }
    // Very narrow displays: the cover above the title.
    final side = fit(
      [
        width - 2 * inset,
        height * 0.3,
        height - meta - controlsHeight - 4 * inset,
      ].reduce(math.min),
    );
    final header = side == 0 ? meta : side + inset + meta;
    return NowPlayingGeometry(
      artworkSize: side,
      sideBySide: false,
      compactMetadata: compact,
      lyricsHeight: height - topInset - header - inset - controlsHeight,
    );
  }
}

/// The display's backdrop colours, interpolated as one value when the
/// cover changes.
@immutable
class _Backdrop {
  final Color top;
  final Color bottom;
  final Color glow;

  const _Backdrop({
    required this.top,
    required this.bottom,
    required this.glow,
  });

  /// No cover, or its colours could not be read: OLED black.
  static const black = _Backdrop(
    top: Color(0xFF000000),
    bottom: Color(0xFF000000),
    glow: Color(0x00000000),
  );

  factory _Backdrop.of(ArtworkPalette? palette) => palette == null
      ? black
      : _Backdrop(
          top: palette.ambient,
          bottom: palette.depth,
          glow: palette.glow,
        );

  static _Backdrop lerp(_Backdrop a, _Backdrop b, double t) => _Backdrop(
    top: Color.lerp(a.top, b.top, t)!,
    bottom: Color.lerp(a.bottom, b.bottom, t)!,
    glow: Color.lerp(a.glow, b.glow, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is _Backdrop &&
      other.top == top &&
      other.bottom == bottom &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(top, bottom, glow);
}

class _BackdropTween extends Tween<_Backdrop> {
  _BackdropTween({required super.end});

  @override
  _Backdrop lerp(double t) => _Backdrop.lerp(begin!, end!, t);
}

/// The album cover, its title and an information [panel] over a backdrop
/// coloured from the cover. Only the display is tinted; with no cover it
/// stays OLED black.
class NowPlayingArtworkScene extends ConsumerStatefulWidget {
  final String? artworkPath;
  final String heroTag;
  final Widget panel;

  /// Tapping or long-pressing the cover (the classic select gestures).
  final VoidCallback? onArtworkTap;
  final VoidCallback? onArtworkLongPress;

  const NowPlayingArtworkScene({
    super.key,
    required this.artworkPath,
    required this.heroTag,
    required this.panel,
    this.onArtworkTap,
    this.onArtworkLongPress,
  });

  @override
  ConsumerState<NowPlayingArtworkScene> createState() =>
      _NowPlayingArtworkSceneState();
}

class _NowPlayingArtworkSceneState
    extends ConsumerState<NowPlayingArtworkScene> {
  /// Null while there is no cover to take colours from.
  ArtworkPalette? _palette;
  Object? _paletteKey;

  static bool _isPlaceholder(ImageProvider provider) =>
      provider is AssetImage &&
      provider.assetName == Assets.defaultAlbumCoverImage;

  void _updatePalette(ImageProvider provider) {
    final path = widget.artworkPath;
    if (path == null) {
      // Any extraction still running for the previous cover is ignored.
      _paletteKey = null;
      _palette = null;
      return;
    }
    // A remote cover still downloading shows the placeholder; the previous
    // colours stay until the real cover arrives, so nothing flashes.
    if (_isPlaceholder(provider) || path == _paletteKey) return;
    _paletteKey = path;
    unawaited(_resolve(path, provider));
  }

  /// Palettes are extracted once per cover and cached; the backdrop then
  /// animates implicitly, never recomputed per frame. A result for a cover
  /// that is no longer showing is dropped.
  Future<void> _resolve(String key, ImageProvider provider) async {
    final palette = await ArtworkPaletteCache.of(key, provider);
    final usable = palette == ArtworkPalette.fallback ? null : palette;
    if (mounted && _paletteKey == key && usable != _palette) {
      setState(() => _palette = usable);
    }
  }

  Widget _artwork(
    BuildContext context,
    ImageProvider provider,
    double side,
    Duration transition,
  ) {
    // Decode at display size; covers are never shown larger than this.
    final cacheWidth = (side * MediaQuery.devicePixelRatioOf(context)).round();
    final radius = BorderRadius.circular((side * 0.045).clamp(4.0, 12.0));
    return GestureDetector(
      onTap: widget.onArtworkTap,
      onLongPress: widget.onArtworkLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: const Color(0x40000000),
              blurRadius: (side * 0.16).clamp(10.0, 32.0),
              offset: Offset(0, (side * 0.025).clamp(2.0, 5.0)),
            ),
          ],
        ),
        child: SizedBox.square(
          key: const ValueKey('now-playing-artwork'),
          dimension: side,
          child: AnimatedSwitcher(
            duration: transition,
            // Only the incoming cover may take part in hero flights.
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [
                for (final child in previous)
                  HeroMode(enabled: false, child: child),
                ?current,
              ],
            ),
            child: Hero(
              key: ValueKey(widget.artworkPath),
              tag: widget.heroTag,
              child: ClipRRect(
                borderRadius: radius,
                // The whole cover, never cropped or zoomed.
                child: Image(
                  image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Image.asset(
                    Assets.defaultAlbumCoverImage,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(NowPlayingGeometry geometry, Widget artwork, Widget panel) {
    const inset = NowPlayingGeometry.inset;
    final side = geometry.artworkSize;
    final metadata = NowPlayingMetadata(compact: geometry.compactMetadata);
    if (geometry.sideBySide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (side > 0)
            Padding(
              // Top-aligned with the title beside it.
              padding: const EdgeInsets.fromLTRB(
                inset,
                NowPlayingGeometry.topInset,
                0,
                0,
              ),
              child: Align(alignment: Alignment.topCenter, child: artwork),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                inset,
                NowPlayingGeometry.topInset,
                inset,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  metadata,
                  const SizedBox(height: inset),
                  Expanded(child: panel),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        inset,
        NowPlayingGeometry.topInset,
        inset,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (geometry.titleBesideArtwork)
            SizedBox(
              height: geometry.headerHeight,
              child: Row(
                children: [
                  if (side > 0) ...[artwork, const SizedBox(width: inset)],
                  Expanded(child: metadata),
                ],
              ),
            )
          else ...[
            if (side > 0) ...[
              Center(child: artwork),
              const SizedBox(height: inset),
            ],
            metadata,
          ],
          const SizedBox(height: inset),
          Expanded(child: panel),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = artworkImage(ref, widget.artworkPath);
    _updatePalette(provider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final transition = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 450);
    final palette = _palette ?? ArtworkPalette.fallback;

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = NowPlayingGeometry.of(constraints.biggest);
        final side = geometry.artworkSize;
        final artwork = side == 0
            ? const SizedBox.shrink()
            : _artwork(context, provider, side, transition);
        // The light falls from where the cover sits.
        final glowCenter = geometry.sideBySide
            ? const Alignment(-0.6, 0)
            : geometry.titleBesideArtwork
            ? const Alignment(-0.6, -0.8)
            : const Alignment(0, -0.7);
        final panel = KeyedSubtree(
          key: const ValueKey('now-playing-panel'),
          child: widget.panel,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            // Only the backdrop repaints while colours change; the content
            // above it is built once per palette.
            TweenAnimationBuilder<_Backdrop>(
              tween: _BackdropTween(end: _Backdrop.of(_palette)),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 550),
              curve: Curves.easeInOut,
              builder: (context, backdrop, _) => DecoratedBox(
                key: const ValueKey('now-playing-backdrop'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [backdrop.top, backdrop.bottom],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: glowCenter,
                      radius: 0.9,
                      colors: [
                        backdrop.glow,
                        backdrop.glow.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            CupertinoTheme(
              data: CupertinoTheme.of(context)
                  .copyWith(brightness: Brightness.dark),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: CupertinoColors.white),
                child: ArtworkAccent(
                  palette: palette,
                  child: _layout(geometry, artwork, panel),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
