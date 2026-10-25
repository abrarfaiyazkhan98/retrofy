import 'dart:typed_data';

import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 4x4 RGBA image filled with one colour.
Uint8List solid(int r, int g, int b) => Uint8List.fromList([
  for (var i = 0; i < 16; i++) ...[r, g, b, 255],
]);

/// An 8x8 RGBA image, [split] of it in one colour and the rest in another.
Uint8List twoTone(List<int> a, List<int> b, {double split = 0.5}) {
  final first = (64 * split).round();
  return Uint8List.fromList([
    for (var i = 0; i < 64; i++) ...[...(i < first ? a : b), 255],
  ]);
}

double hueOf(Color color) => HSLColor.fromColor(color).hue;

double hueGap(Color a, Color b) {
  final d = (hueOf(a) - hueOf(b)).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void main() {
  group('artwork_palette', () {
    final covers = {
      'white': solid(255, 255, 255),
      'black': solid(0, 0, 0),
      'yellow': solid(255, 230, 0),
      'red': solid(220, 20, 40),
      'grey': solid(128, 128, 128),
    };

    for (final entry in covers.entries) {
      test('white text stays readable over a ${entry.key} cover', () {
        final palette = ArtworkPalette.fromPixels(entry.value);
        expect(palette.whiteTextContrast, greaterThanOrEqualTo(4.5));
      });
    }

    test('saturated covers lend their hue to the accent', () {
      final palette = ArtworkPalette.fromPixels(solid(220, 20, 40));
      expect(palette.accent, isNot(ArtworkPalette.fallback.accent));
      expect(
        (palette.accent.r * 255).round(),
        greaterThan((palette.accent.b * 255).round()),
      );
    });

    test('greyscale and transparent covers use the classic accent', () {
      expect(
        ArtworkPalette.fromPixels(solid(128, 128, 128)).accent,
        ArtworkPalette.fallback.accent,
      );
      expect(
        ArtworkPalette.fromPixels(Uint8List(64)),
        same(ArtworkPalette.fallback),
      );
    });

    test('two-colour covers glow in both of their colours', () {
      final palette = ArtworkPalette.fromPixels(
        twoTone([20, 60, 200], [230, 120, 20], split: 0.6),
      );
      expect(hueOf(palette.primary), closeTo(225, 20), reason: 'blue first');
      expect(hueOf(palette.secondary), closeTo(30, 20));
    });

    test('single-colour covers get a neighbouring shade, not a new hue', () {
      final palette = ArtworkPalette.fromPixels(solid(30, 150, 60));
      expect(palette.primary, isNot(palette.secondary));
      expect(hueGap(palette.primary, palette.secondary), lessThan(40));
    });

    test('glow colours are never neon or near-white', () {
      for (final cover in [
        solid(255, 255, 255),
        solid(0, 255, 0),
        solid(255, 0, 255),
        solid(0, 0, 0),
      ]) {
        final palette = ArtworkPalette.fromPixels(cover);
        for (final color in [palette.primary, palette.secondary]) {
          final hsl = HSLColor.fromColor(color);
          expect(hsl.lightness, inInclusiveRange(0.23, 0.49));
          expect(hsl.saturation, lessThanOrEqualTo(0.71));
        }
      }
    });

    test('greyscale covers keep a neutral glow', () {
      final palette = ArtworkPalette.fromPixels(solid(128, 128, 128));
      expect(HSLColor.fromColor(palette.primary).saturation, lessThan(0.05));
    });

    test('palettes blend smoothly between tracks', () {
      final a = ArtworkPalette.fromPixels(solid(220, 20, 40));
      final b = ArtworkPalette.fromPixels(solid(20, 60, 200));
      expect(ArtworkPalette.lerp(a, b, 0), a);
      expect(ArtworkPalette.lerp(a, b, 1), b);
      final mid = ArtworkPalette.lerp(a, b, 0.5);
      expect(mid, isNot(a));
      expect(mid, isNot(b));
      expect(ArtworkPalette.fromPixels(solid(220, 20, 40)), a);
    });
  });
}
