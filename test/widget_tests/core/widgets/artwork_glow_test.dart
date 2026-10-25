import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:classipod/core/theme/glow_rendering.dart';
import 'package:classipod/core/widgets/artwork_glow.dart';
import 'package:classipod/features/settings/models/artwork_glow.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const red = ArtworkPalette(
  scrim: Color(0xFF200A0A),
  accent: Color(0xFFFF6060),
  primary: Color(0xFF7A2020),
  secondary: Color(0xFF7A4020),
);
const blue = ArtworkPalette(
  scrim: Color(0xFF0A0A20),
  accent: Color(0xFF6080FF),
  primary: Color(0xFF20307A),
  secondary: Color(0xFF40207A),
);

void main() {
  group('artwork_glow', () {
    late ArtworkGlowStyle style;
    late AnimationQuality quality;

    Future<void> pump(
      WidgetTester tester,
      ArtworkPalette palette, {
      bool reduceMotion = false,
      bool visible = true,
    }) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          glowRenderingProvider.overrideWith(
            (ref, reduce) => GlowRendering.resolve(
              style: style,
              quality: quality,
              reduceMotion: reduce,
              batterySaver: false,
            ),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: TickerMode(
            enabled: visible,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ArtworkGlow(palette: palette),
            ),
          ),
        ),
      ),
    );

    setUp(() {
      style = ArtworkGlowStyle.dynamic;
      quality = AnimationQuality.auto;
    });

    testWidgets('animates while shown', (tester) async {
      await pump(tester, red);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('does no frame work in Battery Saver quality', (tester) async {
      quality = AnimationQuality.batterySaver;
      await pump(tester, red);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('does no frame work with reduced motion', (tester) async {
      await pump(tester, red, reduceMotion: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('pauses while its screen is hidden', (tester) async {
      await pump(tester, red, visible: false);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('Off shows the plain base colour', (tester) async {
      style = ArtworkGlowStyle.off;
      await pump(tester, red);
      expect(find.byType(CustomPaint), findsNothing);
      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
        red.base,
      );
    });

    testWidgets('track changes blend palettes without jumps', (tester) async {
      style = ArtworkGlowStyle.off;
      await pump(tester, red);
      Color base() => tester.widget<ColoredBox>(find.byType(ColoredBox)).color;
      await pump(tester, blue);
      expect(base(), red.base, reason: 'old colours stay while blending');
      await tester.pump(const Duration(milliseconds: 350));
      final halfway = base();
      expect(halfway, isNot(red.base));
      expect(halfway, isNot(blue.base));
      // A rapid skip back starts from the colour on screen, not from blue.
      await pump(tester, red);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        (base().r - halfway.r).abs(),
        lessThan(0.05),
        reason: 'no flash to the skipped palette',
      );
      await tester.pumpAndSettle();
      expect(base(), red.base);
    });

    testWidgets('reduced motion switches palettes at once', (tester) async {
      style = ArtworkGlowStyle.off;
      await pump(tester, red, reduceMotion: true);
      await pump(tester, blue, reduceMotion: true);
      await tester.pump();
      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
        blue.base,
      );
    });
  });
}
