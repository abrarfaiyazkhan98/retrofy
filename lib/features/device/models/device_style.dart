import 'package:classipod/core/constants/app_palette.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// Colours of the physical iPod around the display. The body is pure OLED
/// black (#000000) with no gradient, texture or shadow; only the click wheel
/// keeps a dark surface and the centre button a subtle tactile shading.
@immutable
class DeviceStyle {
  final Color frameColor;
  final Color controlBackgroundColor;
  final Color controlBorderColor;
  final List<Color> innerButtonGradientColors;
  final Color buttonAccentColor;
  final Color buttonIconColor;

  const DeviceStyle._({
    required this.frameColor,
    required this.controlBackgroundColor,
    required this.controlBorderColor,
    required this.innerButtonGradientColors,
    required this.buttonAccentColor,
    required this.buttonIconColor,
  });

  static const oledBlack = DeviceStyle._(
    frameColor: Color(0xFF000000),
    controlBackgroundColor: AppPalette.darkDeviceControlBackgroundColor,
    controlBorderColor: Color(0xFF000000),
    innerButtonGradientColors: [
      AppPalette.darkDeviceControlInnerButtonGradientColor1,
      AppPalette.darkDeviceControlInnerButtonGradientColor2,
    ],
    buttonAccentColor: CupertinoColors.white,
    buttonIconColor: CupertinoColors.white,
  );
}
