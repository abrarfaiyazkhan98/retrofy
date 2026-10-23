import 'package:classipod/core/theme/glow_rendering.dart';
import 'package:classipod/features/settings/models/artwork_glow.dart';
import 'package:flutter_test/flutter_test.dart';

GlowRendering resolve({
  ArtworkGlowStyle style = ArtworkGlowStyle.dynamic,
  AnimationQuality quality = AnimationQuality.auto,
  bool reduceMotion = false,
  bool batterySaver = false,
  bool lagging = false,
}) => GlowRendering.resolve(
  style: style,
  quality: quality,
  reduceMotion: reduceMotion,
  batterySaver: batterySaver,
  lagging: lagging,
);

void main() {
  group('glow_quality_profiles', () {
    test('Auto animates the full mesh on a capable device', () {
      final rendering = resolve();
      expect(rendering.visible, isTrue);
      expect(rendering.animated, isTrue);
      expect(rendering.fields, 5);
      expect(rendering.intensity, 1);
    });

    test('Auto turns still under Battery Saver', () {
      final rendering = resolve(batterySaver: true);
      expect(rendering.visible, isTrue);
      expect(rendering.animated, isFalse);
    });

    test('Auto steps down to balanced once frames drop', () {
      final rendering = resolve(lagging: true);
      expect(rendering.animated, isTrue);
      expect(rendering.fields, 3);
      expect(rendering.frameInterval, greaterThan(resolve().frameInterval));
    });

    test('a chosen quality is kept regardless of conditions', () {
      expect(
        resolve(quality: AnimationQuality.high, batterySaver: true).fields,
        5,
      );
      expect(resolve(quality: AnimationQuality.balanced).fields, 3);
      expect(resolve(quality: AnimationQuality.batterySaver).animated, isFalse);
    });

    test('reduced motion always gives a still glow', () {
      for (final quality in AnimationQuality.values) {
        expect(
          resolve(quality: quality, reduceMotion: true).animated,
          isFalse,
          reason: quality.name,
        );
      }
    });

    test('Subtle is gentler than Dynamic and Off draws nothing', () {
      expect(
        resolve(style: ArtworkGlowStyle.subtle).intensity,
        lessThan(resolve().intensity),
      );
      expect(resolve(style: ArtworkGlowStyle.off), GlowRendering.off);
    });
  });
}
