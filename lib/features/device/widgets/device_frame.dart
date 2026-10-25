import 'package:classipod/core/constants/keys.dart';
import 'package:classipod/features/device/models/device_layout.dart';
import 'package:classipod/features/device/models/device_style.dart';
import 'package:classipod/features/device/widgets/device_controls.dart';
import 'package:classipod/features/device/widgets/device_screen.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// The iPod body: pure OLED black around the display and the click wheel,
/// sized from the window it is given so split-screen and pop-up windows get
/// the same proportions as full screen.
class DeviceFrame extends StatelessWidget {
  final Widget child;

  const DeviceFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DeviceStyle.oledBlack.frameColor,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 30, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 960, maxWidth: 450),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = DeviceLayout.fit(constraints.maxHeight);
                return Column(
                  children: [
                    DeviceScreen(
                      key: deviceScreenGlobalKey,
                      height: layout.screenHeight,
                      child: child,
                    ),
                    SizedBox(height: layout.gap),
                    SizedBox(
                      height: layout.wheelHeight,
                      child: Center(
                        child: DeviceControls(key: deviceControlsGlobalKey),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
