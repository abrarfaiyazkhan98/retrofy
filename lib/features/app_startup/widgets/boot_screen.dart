import 'dart:async';

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/repositories/library/library_progress.dart';
import 'package:classipod/features/app_startup/controllers/app_startup_controller.dart';
import 'package:classipod/features/app_startup/controllers/splash_controller.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How far startup has got, from the steps that actually run: app services,
/// then the audio permission and library scan (by songs indexed of the
/// total found), then restoring the playback session. Null while there is
/// nothing to show yet; 1 when startup is complete.
double bootProgress({
  required AsyncValue<void> startup,
  required AsyncValue<void>? splash,
  required LibraryProgress library,
}) {
  if (!startup.hasValue) return 0;
  if (splash == null) return 0.15;
  if (splash.hasValue && !splash.isLoading) return 1;
  return switch (library.phase) {
    LibraryPhase.discovering => 0.2,
    LibraryPhase.complete => 0.92,
    _ when library.songsTotal > 0 =>
      0.2 + 0.7 * (library.songsLoaded / library.songsTotal).clamp(0.0, 1.0),
    _ => 0.2,
  };
}

/// Retrofy's boot screen: black, the white Retrofy logo and a thin
/// progress bar, laid over the whole app while it starts. It covers both
/// startup stages so the logo fades in once, fills the bar when startup
/// completes and fades away to reveal the menu. It steps aside at once if
/// startup fails, so error screens and dialogs underneath stay usable.
class BootScreen extends ConsumerStatefulWidget {
  /// Without any progress for this long, the boot screen gives way to the
  /// iPod loading screen underneath, which shows details and recovery.
  final Duration stallTimeout;

  const BootScreen({
    super.key,
    this.stallTimeout = const Duration(seconds: 20),
  });

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen> {
  static const _fill = Duration(milliseconds: 250);
  static const _hold = Duration(milliseconds: 150);
  static const _fade = Duration(milliseconds: 300);
  static const _logoSize = 118.0;

  final _started = DateTime.now();
  bool _logoVisible = false;
  bool _leaving = false;
  bool _fading = false;
  bool _gone = false;
  double _lastProgress = 0;
  Timer? _stall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _logoVisible = true);
    });
    _armStallTimer();
  }

  void _armStallTimer() {
    _stall?.cancel();
    _stall = Timer(widget.stallTimeout, () => _leave(immediately: true));
  }

  Future<void> _leave({required bool immediately}) async {
    if (_leaving) return;
    _stall?.cancel();
    _leaving = true;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (immediately || reduceMotion) {
      setState(() => _gone = true);
      return;
    }
    // Let the bar finish filling, hold briefly, then fade. A quick (warm)
    // start skips the hold so decoration never delays the app.
    final quick =
        DateTime.now().difference(_started) < const Duration(seconds: 1);
    await Future<void>.delayed(quick ? _fill : _fill + _hold);
    if (!mounted) return;
    setState(() => _fading = true);
    await Future<void>.delayed(_fade);
    if (mounted) setState(() => _gone = true);
  }

  @override
  void dispose() {
    _stall?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final startup = ref.watch(appStartupControllerProvider);
    // The splash controller requests permissions and scans the library, so
    // it may only start once the app's services are ready.
    final splash = startup.hasValue
        ? ref.watch(splashControllerProvider)
        : null;
    final progress = bootProgress(
      startup: startup,
      splash: splash,
      library: ref.watch(libraryProgressProvider),
    );
    if (progress != _lastProgress) {
      _lastProgress = progress;
      _armStallTimer();
    }
    final failed = startup.hasError || (splash?.hasError ?? false);
    if (failed || progress >= 1) {
      scheduleMicrotask(() => _leave(immediately: failed));
    }
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final width = MediaQuery.maybeSizeOf(context)?.width ?? 360;
    final barWidth = (width * 0.46).clamp(140.0, 220.0);

    return IgnorePointer(
      ignoring: _leaving,
      child: AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: reduceMotion ? Duration.zero : _fade,
        child: Semantics(
          label: 'Retrofy',
          value: '${(progress * 100).round()}%',
          child: ColoredBox(
            color: const Color(0xFF000000),
            // The logo sits exactly where, and as large as, Android's system
            // splash draws it, so the hand-over does not jump.
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  opacity: _logoVisible ? 1 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  child: Image.asset(
                    Assets.retrofyLogo,
                    width: _logoSize,
                    height: _logoSize,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, _logoSize / 2 + 72),
                  child: _ProgressBar(
                    progress: progress,
                    width: barWidth,
                    duration: reduceMotion ? Duration.zero : _fill,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final double width;
  final Duration duration;

  const _ProgressBar({
    required this.progress,
    required this.width,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    const height = 5.0;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF3F3F3F),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, value, _) => Container(
          width: width * value,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}
