import 'package:classipod/features/device/models/device_style.dart';
import 'package:classipod/features/device/widgets/device_frame.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/settings/models/click_wheel_sensitivity.dart';
import 'package:classipod/features/settings/models/click_wheel_size.dart';
import 'package:classipod/features/settings/models/settings_preferences_model.dart';
import 'package:classipod/l10n/generated/app_localizations.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SettingsModel extends Fake implements SettingsPreferencesModel {
  @override
  ClickWheelSize get clickWheelSize => ClickWheelSize.medium;

  @override
  ClickWheelSensitivity get clickWheelSensitivity =>
      ClickWheelSensitivity.medium;

  @override
  bool get isTouchScreenEnabled => true;
}

class _Settings extends SettingsPreferencesControllerNotifier {
  @override
  SettingsPreferencesModel build() => _SettingsModel();
}

Future<void> _pumpFrame(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsPreferencesControllerProvider.overrideWith(_Settings.new),
      ],
      child: const CupertinoApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DeviceFrame(child: SizedBox.expand(key: Key('display'))),
      ),
    ),
  );
}

void main() {
  group('oled_device', () {
    test('the body is pure #000000', () {
      expect(DeviceStyle.oledBlack.frameColor, const Color(0xFF000000));
    });

    testWidgets('the body is one flat black fill without shadows', (
      tester,
    ) async {
      await _pumpFrame(tester, const Size(412, 915));
      final body = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(DeviceFrame),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(body.color, const Color(0xFF000000));
      final shadows = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(DeviceFrame),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.boxShadow?.isNotEmpty ?? false);
      expect(shadows, isEmpty);
      final gradients = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(DeviceFrame),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where(
            (decoration) =>
                decoration.gradient != null &&
                decoration.shape != BoxShape.circle,
          );
      expect(gradients, isEmpty, reason: 'only the centre button is shaded');
    });

    testWidgets('the display reports its own size, not the window', (
      tester,
    ) async {
      // A half-height split-screen window on a wide device.
      await _pumpFrame(tester, const Size(900, 520));
      final display = tester.element(find.byKey(const Key('display')));
      final reported = MediaQuery.sizeOf(display);
      final actual = tester.getSize(find.byKey(const Key('display')));
      expect(reported, actual);
      expect(tester.takeException(), isNull);
    });
  });
}
