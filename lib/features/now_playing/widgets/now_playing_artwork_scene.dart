import 'dart:async';

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

/// Album artwork filling the Now Playing screen with a scrim tinted from the
/// cover, and [builder]'s content laid over it in light-on-dark colours.
class NowPlayingArtworkScene extends ConsumerStatefulWidget {
  final String? artworkPath;
  final String heroTag;

  /// Darkens the whole cover (used while lyrics are shown).
  final bool dimmed;
  final Widget child;

  const NowPlayingArtworkScene({
    super.key,
    required this.artworkPath,
    required this.heroTag,
    required this.child,
    this.dimmed = false,
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

  Future<void> _resolve(String key, ImageProvider provider) async {
    final palette = await ArtworkPaletteCache.of(key, provider);
    {
      if (mounted && _paletteKey == key && palette != _palette) {
        setState(() => _palette = palette);
      }
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
    final scrim = _palette.scrim;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Decode at display size; covers are never shown larger than this.
        final cacheWidth =
            (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                .round();
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scrim),
            AnimatedSwitcher(
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
                child: Image(
                  image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Image.asset(
                    Assets.defaultAlbumCoverImage,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: transition,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: widget.dimmed
                      ? [
                          scrim.withValues(alpha: 0.78),
                          scrim.withValues(alpha: 0.86),
                          scrim.withValues(alpha: 0.94),
                        ]
                      : [
                          scrim.withValues(alpha: 0.45),
                          scrim.withValues(alpha: 0),
                          scrim.withValues(alpha: 0.6),
                          scrim.withValues(alpha: 0.94),
                        ],
                  stops: widget.dimmed ? null : const [0, 0.18, 0.55, 1],
                ),
              ),
            ),
            CupertinoTheme(
              data: CupertinoTheme.of(context)
                  .copyWith(brightness: Brightness.dark),
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  color: CupertinoColors.white,
                  shadows: [Shadow(blurRadius: 6, color: Color(0x99000000))],
                ),
                child: ArtworkAccent(palette: _palette, child: widget.child),
              ),
            ),
          ],
        );
      },
    );
  }
}
