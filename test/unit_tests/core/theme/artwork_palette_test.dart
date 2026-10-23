import 'dart:typed_data';

import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 4x4 RGBA image filled with one colour.
Uint8List solid(int r, int g, int b) => Uint8List.fromList([
  for (var i = 0; i < 16; i++) ...[r, g, b, 255],
]);

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
  });
}
