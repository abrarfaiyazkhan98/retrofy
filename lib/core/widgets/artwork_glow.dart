import 'dart:async';
import 'dart:ui' as ui;

import 'package:battery_plus/battery_plus.dart';
import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:classipod/core/theme/glow_rendering.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/status_bar/controller/battery_controller.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Android's Battery Saver (or the platform's equivalent) is on.
/// Re-read when the charging state changes and when Retrofy returns to the
/// foreground; platforms without the concept report false.
final batterySaverProvider = FutureProvider<bool>((ref) async {
  ref.watch(onBatteryStateChangeProvider);
  try {
    return await Battery().isInBatterySaveMode;
  } catch (_) {
    return false;
  }
});

/// Set once this session's device has dropped frames while the glow was
/// animating, so Auto quality stays on the balanced profile afterwards.
final glowLaggingProvider = NotifierProvider<GlowLaggingNotifier, bool>(
  GlowLaggingNotifier.new,
);

class GlowLaggingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void report() => state = true;
}

/// The glow profile for the current settings and device conditions.
final glowRenderingProvider = Provider.autoDispose.family<GlowRendering, bool>((
  ref,
  reduceMotion,
) {
  final settings = ref.watch(settingsPreferencesControllerProvider);
  return GlowRendering.resolve(
    style: settings.artworkGlow,
    quality: settings.animationQuality,
    reduceMotion: reduceMotion,
    batterySaver: ref.watch(batterySaverProvider).value ?? false,
    lagging: ref.watch(glowLaggingProvider),
  );
});

/// The artwork's colours radiating into the screen: a dark base, slowly
/// drifting colour fields and a halo around [haloRect], drawn by one shader
/// pass behind the content. The cover itself is drawn by the caller, sharp,
/// on top of this.
class ArtworkGlow extends ConsumerStatefulWidget {
  final ArtworkPalette palette;

  /// The artwork's frame in this widget's coordinates; null: no halo.
  final Rect? haloRect;
  final double haloRadius;

  /// 0..1: calms the glow behind lyrics.
  final double calm;

  /// Scales the settings' intensity, e.g. lower on the regular Now Playing.
  final double strength;

  const ArtworkGlow({
    super.key,
    required this.palette,
    this.haloRect,
    this.haloRadius = 12,
    this.calm = 0,
    this.strength = 1,
  });

  @override
  ConsumerState<ArtworkGlow> createState() => _ArtworkGlowState();
}

class _ArtworkGlowState extends ConsumerState<ArtworkGlow>
    with TickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _program;

  ui.FragmentShader? _shader;
  Ticker? _ticker;
  final _time = ValueNotifier<double>(0);
  Duration _lastFrame = Duration.zero;
  Duration _frameInterval = const Duration(milliseconds: 33);

  late ArtworkPalette _from = widget.palette;
  late ArtworkPalette _to = widget.palette;
  late final _blend = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );
  late final _calm = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: widget.calm,
  );
  late final AppLifecycleListener _lifecycle;

  // Frame-drop watch while animating; see [_onTimings].
  int _frames = 0;
  int _slowFrames = 0;
  bool _watchingTimings = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(batterySaverProvider),
    );
    unawaited(_loadShader());
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_program ??= ui.FragmentProgram.fromAsset(
        'shaders/artwork_glow.frag',
      ));
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (error) {
      // Gradient fallback below; the shader only adds motion and the halo.
      debugPrint('Artwork glow shader unavailable: ${error.runtimeType}');
    }
  }

  @override
  void didUpdateWidget(ArtworkGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.palette != _to) {
      // Start from wherever a running blend has got to, so rapid skips
      // never jump.
      _from = ArtworkPalette.lerp(_from, _to, _blend.value);
      _to = widget.palette;
      if (MediaQuery.disableAnimationsOf(context)) {
        _blend.value = 1;
      } else {
        unawaited(_blend.forward(from: 0));
      }
    }
    if (widget.calm != oldWidget.calm) {
      unawaited(_calm.animateTo(widget.calm));
    }
  }

  void _applyRendering(GlowRendering rendering) {
    _frameInterval = rendering.frameInterval;
    final animate = rendering.visible && rendering.animated;
    if (animate) {
      _ticker ??= createTicker(_onTick);
      if (!_ticker!.isActive) unawaited(_ticker!.start());
      _watchTimings(rendering.fields > 3);
    } else {
      _ticker?.stop();
      _watchTimings(false);
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastFrame < _frameInterval) return;
    _lastFrame = elapsed;
    // Wrapped so the shader's float time keeps full precision; the drift
    // periods are short enough that the wrap falls at an unnoticed moment.
    _time.value = (elapsed.inMilliseconds / 1000) % 3600;
  }

  void _watchTimings(bool watch) {
    if (watch == _watchingTimings) return;
    _watchingTimings = watch;
    if (watch) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    } else {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
  }

  /// Auto quality steps down for the session if over a fifth of 180 frames
  /// miss the display's frame budget while the full mesh animates.
  void _onTimings(List<ui.FrameTiming> timings) {
    final refresh =
        ui.PlatformDispatcher.instance.displays.firstOrNull?.refreshRate ?? 60;
    final budget = Duration(microseconds: (1e6 / refresh).round());
    for (final timing in timings) {
      _frames++;
      if (timing.rasterDuration > budget || timing.buildDuration > budget) {
        _slowFrames++;
      }
    }
    if (_frames < 180) return;
    if (_slowFrames * 5 > _frames) {
      ref.read(glowLaggingProvider.notifier).report();
    }
    _frames = 0;
    _slowFrames = 0;
  }

  @override
  void dispose() {
    _watchTimings(false);
    _lifecycle.dispose();
    _ticker?.dispose();
    _blend.dispose();
    _calm.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rendering = ref.watch(
      glowRenderingProvider(MediaQuery.disableAnimationsOf(context)),
    );
    _applyRendering(rendering);
    if (!rendering.visible) {
      return AnimatedBuilder(
        animation: _blend,
        builder: (_, _) => ColoredBox(
          color: ArtworkPalette.lerp(_from, _to, _blend.value).base,
        ),
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GlowPainter(
          shader: _shader,
          time: _time,
          blend: _blend,
          calm: _calm,
          from: _from,
          to: _to,
          fields: rendering.fields,
          intensity: rendering.intensity * widget.strength,
          haloRect: widget.haloRect,
          haloRadius: widget.haloRadius,
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final ui.FragmentShader? shader;
  final ValueListenable<double> time;
  final Animation<double> blend;
  final Animation<double> calm;
  final ArtworkPalette from;
  final ArtworkPalette to;
  final int fields;
  final double intensity;
  final Rect? haloRect;
  final double haloRadius;

  _GlowPainter({
    required this.shader,
    required this.time,
    required this.blend,
    required this.calm,
    required this.from,
    required this.to,
    required this.fields,
    required this.intensity,
    required this.haloRect,
    required this.haloRadius,
  }) : super(repaint: Listenable.merge([time, blend, calm]));

  @override
  void paint(Canvas canvas, Size size) {
    final palette = ArtworkPalette.lerp(from, to, blend.value);
    final rect = Offset.zero & size;
    final shader = this.shader;
    if (shader == null) {
      _paintFallback(canvas, size, palette);
      return;
    }
    // FlutterFragCoord is in this canvas's logical coordinates.
    var i = 0;
    void set(double value) => shader.setFloat(i++, value);
    void colour(Color c) {
      set(c.r);
      set(c.g);
      set(c.b);
    }

    set(size.width);
    set(size.height);
    set(time.value);
    set(intensity);
    set(fields.toDouble());
    final halo = haloRect;
    set(halo?.left ?? 0);
    set(halo?.top ?? 0);
    set(halo?.width ?? 0);
    set(halo?.height ?? 0);
    set(haloRadius);
    set(calm.value);
    colour(palette.base);
    colour(palette.primary);
    colour(palette.secondary);
    colour(palette.accent);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  /// Still gradient for devices where the shader cannot load.
  void _paintFallback(Canvas canvas, Size size, ArtworkPalette palette) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = palette.base);
    final k = intensity * (1 - calm.value * 0.65);
    void glow(Alignment at, Color colour, double radius, double opacity) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: at,
            radius: radius,
            colors: [
              colour.withValues(alpha: opacity * k),
              colour.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    glow(const Alignment(-0.45, -0.5), palette.primary, 0.9, 0.8);
    glow(const Alignment(0.5, -0.2), palette.secondary, 0.8, 0.7);
    glow(const Alignment(-0.1, 0.6), palette.primary, 0.9, 0.5);
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.shader != shader ||
      old.from != from ||
      old.to != to ||
      old.fields != fields ||
      old.intensity != intensity ||
      old.haloRect != haloRect ||
      old.haloRadius != haloRadius;
}
