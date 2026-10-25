import 'package:cupertino_ui/cupertino_ui.dart';

/// Black, like the boot screen above it, so nothing flashes before it.
class AppStartupLoading extends StatelessWidget {
  const AppStartupLoading({super.key});

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF000000));
}
