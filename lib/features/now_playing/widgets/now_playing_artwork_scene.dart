import 'dart:async';
import 'dart:math' as math;

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:classipod/core/widgets/artwork_image.dart';
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

/// Where the cover and the information panel go in a window of a given
/// size. Pure geometry, so every window shape can be tested.
@immutable
class NowPlayingGeometry {
  /// Side of the square cover; 0 hides it.
  final double artworkSize;

  /// Cover beside the panel instead of above it (wide, short windows).
  final bool sideBySide;

  const NowPlayingGeometry({
    required this.artworkSize,
    required this.sideBySide,
  });

  /// Height the panel needs for the title, artist, progress bar and the
  /// Go to Artist row, without lyrics.
  static const panelMinHeight = 150.0;

  /// Width the panel needs for the progress row and Go to Artist.
  static const panelMinWidth = 240.0;

  /// The cover is dropped below this size rather than shown as a stamp.
  static const minArtwork = 56.0;

  factory NowPlayingGeometry.of(Size size) {
    final width = size.width;
    final height = size.height;
    if (width >= height * 1.25 && width >= 320) {
      // Landscape-like windows: the cover fills the height on the left and
      // the panel keeps at least half the width, never under its minimum.
      final side = math.min(
        math.min(height, width * 0.45),
        width - panelMinWidth,
      );
      return NowPlayingGeometry(
        artworkSize: side < minArtwork ? 0 : side,
        sideBySide: true,
      );
    }
    // Portrait: the cover spans the width but leaves the panel room for
    // its controls, and shrinks proportionally in short windows.
    final side = math.min(
      width,
      math.min(height * 0.62, height - panelMinHeight),
    );
    return NowPlayingGeometry(
      artworkSize: side < minArtwork ? 0 : side,
      sideBySide: false,
    );
  }
}

/// The whole album cover with an information [panel] in a colour taken from
/// it. Around them the screen stays OLED black; only the panel is tinted.
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
  ArtworkPalette _palette = ArtworkPalette.fallback;
  Object? _paletteKey;

  void _updatePalette(ImageProvider provider) {
    // The fallback cover shows while remote artwork loads; key by provider
    // type so its palette is never cached under the real cover's path.
    final key = '${widget.artworkPath}|${provider.runtimeType}';
    if (key == _paletteKey) return;
    _paletteKey = key;
    unawaited(_resolve(key, provider));
  }

  /// Palettes are extracted once per cover and cached; the panel colour
  /// then animates implicitly, never recomputed per frame.
  Future<void> _resolve(String key, ImageProvider provider) async {
    final palette = await ArtworkPaletteCache.of(key, provider);
    if (mounted && _paletteKey == key && palette != _palette) {
      setState(() => _palette = palette);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = artworkImage(ref, widget.artworkPath);
    _updatePalette(provider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final transition = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 450);

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = NowPlayingGeometry.of(constraints.biggest);
        final side = geometry.artworkSize;
        // Decode at display size; covers are never shown larger than this.
        final cacheWidth = (side * MediaQuery.devicePixelRatioOf(context))
            .round();
        final artwork = side == 0
            ? const SizedBox.shrink()
            : GestureDetector(
                onTap: widget.onArtworkTap,
                onLongPress: widget.onArtworkLongPress,
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
                      // The whole cover, never cropped or zoomed.
                      child: Image(
                        image: ResizeImage.resizeIfNeeded(
                          cacheWidth,
                          null,
                          provider,
                        ),
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
              );
        final panel = AnimatedContainer(
          key: const ValueKey('now-playing-panel'),
          duration: transition,
          curve: Curves.easeOut,
          color: _palette.panel,
          child: CupertinoTheme(
            data: CupertinoTheme.of(context)
                .copyWith(brightness: Brightness.dark),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: CupertinoColors.white),
              child: ArtworkAccent(palette: _palette, child: widget.panel),
            ),
          ),
        );
        return ColoredBox(
          color: const Color(0xFF000000),
          child: geometry.sideBySide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: artwork),
                    Expanded(child: panel),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: artwork),
                    Expanded(child: panel),
                  ],
                ),
        );
      },
    );
  }
}
