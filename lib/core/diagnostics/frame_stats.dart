import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Opt-in frame timing for measuring smoothness on a device:
/// `--dart-define=RETROFY_FRAME_STATS=true`. Off by default, so normal
/// builds compile this out and pay nothing.
const _enabled = bool.fromEnvironment('RETROFY_FRAME_STATS');

/// Logs build/raster percentiles every few seconds while frames are drawn.
void startFrameStats() {
  if (!_enabled) return;
  final builds = <double>[];
  final rasters = <double>[];
  var windowStart = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      builds.add(timing.buildDuration.inMicroseconds / 1000);
      rasters.add(timing.rasterDuration.inMicroseconds / 1000);
    }
    if (DateTime.now().difference(windowStart) < const Duration(seconds: 3)) {
      return;
    }
    windowStart = DateTime.now();
    final budget =
        1000 /
        (PlatformDispatcher.instance.displays.firstOrNull?.refreshRate ?? 60);
    String summary(List<double> values) {
      values.sort();
      double at(double q) => values[((values.length - 1) * q).round()];
      return 'p50 ${at(.5).toStringAsFixed(2)} p95 ${at(.95).toStringAsFixed(2)} '
          'max ${values.last.toStringAsFixed(2)} ms';
    }

    final over = [
      for (var i = 0; i < builds.length; i++)
        if (builds[i] > budget || rasters[i] > budget) i,
    ].length;
    debugPrint(
      'FrameStats ${builds.length} frames, budget '
      '${budget.toStringAsFixed(2)} ms | build ${summary(builds)} | '
      'raster ${summary(rasters)} | over budget $over',
    );
    builds.clear();
    rasters.clear();
  });
}
