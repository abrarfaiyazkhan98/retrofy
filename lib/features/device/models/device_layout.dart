import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Splits the iPod's usable height between the display and the click wheel:
/// about three quarters for the display, the rest for the wheel, which never
/// shrinks below a size whose buttons stay comfortable to press.
@immutable
class DeviceLayout {
  /// Height of the display, including its 5 px border above and below.
  final double screenHeight;

  /// Space between the display and the wheel.
  final double gap;

  /// Height available to the wheel, which is drawn at most this wide.
  final double wheelHeight;

  const DeviceLayout({
    required this.screenHeight,
    required this.gap,
    required this.wheelHeight,
  });

  static const displayShare = 0.75;

  /// The smallest wheel whose ring buttons (MENU, previous, next,
  /// play/pause) each stay at least 44 dp deep around the centre button.
  static const minWheel = 168.0;

  /// Enough display for the status bar and a few list rows.
  static const minScreen = 220.0;
  static const gapHeight = 16.0;

  factory DeviceLayout.fit(double available) {
    final content = math.max(0.0, available - gapHeight);
    var wheel = math.max(content * (1 - displayShare), minWheel);
    var screen = content - wheel;
    if (screen < minScreen) {
      // Very short windows: keep a usable display, shrink the wheel.
      screen = math.min(minScreen, content);
      wheel = content - screen;
    }
    return DeviceLayout(
      screenHeight: screen,
      gap: gapHeight,
      wheelHeight: wheel,
    );
  }
}
