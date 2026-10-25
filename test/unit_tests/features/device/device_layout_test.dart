import 'package:classipod/features/device/models/device_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('device_layout', () {
    double displayShare(DeviceLayout layout) =>
        layout.screenHeight / (layout.screenHeight + layout.wheelHeight);

    // Usable heights inside the frame for small, standard and large phones
    // and a tall foldable cover screen.
    for (final available in [720.0, 760.0, 840.0, 960.0]) {
      test('gives the display about three quarters at $available', () {
        final layout = DeviceLayout.fit(available);
        expect(displayShare(layout), closeTo(0.75, 0.02));
        expect(
          layout.screenHeight + layout.gap + layout.wheelHeight,
          closeTo(available, 0.001),
        );
      });
    }

    test('the wheel never gets too small to press', () {
      final layout = DeviceLayout.fit(600);
      expect(layout.wheelHeight, greaterThanOrEqualTo(DeviceLayout.minWheel));
      expect(displayShare(layout), lessThan(0.75));
    });

    test('very short windows keep a usable display', () {
      final layout = DeviceLayout.fit(380);
      expect(layout.screenHeight, DeviceLayout.minScreen);
      expect(layout.wheelHeight, greaterThan(0));
    });
  });
}
