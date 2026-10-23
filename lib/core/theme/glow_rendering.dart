import 'package:classipod/features/settings/models/artwork_glow.dart';
import 'package:flutter/foundation.dart';

/// What the artwork glow draws, resolved from the user's settings and the
/// device's current conditions.
@immutable
class GlowRendering {
  /// Nothing is drawn; screens show their plain dark base.
  final bool visible;

  /// False draws one still frame and runs no ticker at all.
  final bool animated;

  /// Colour fields in the mesh: 5 (high) or 3 (balanced).
  final int fields;

  /// Time between redraws. The drift is slow enough that 30 redraws a
  /// second look continuous while halving the work of a 60 Hz redraw.
  final Duration frameInterval;

  /// How far the fields stand out from the base (0..1).
  final double intensity;

  const GlowRendering({
    required this.visible,
    required this.animated,
    required this.fields,
    required this.frameInterval,
    required this.intensity,
  });

  static const off = GlowRendering(
    visible: false,
    animated: false,
    fields: 0,
    frameInterval: Duration.zero,
    intensity: 0,
  );

  /// [lagging] is set once the device has been seen dropping frames while
  /// the glow animates; Auto then steps down to the balanced profile.
  factory GlowRendering.resolve({
    required ArtworkGlowStyle style,
    required AnimationQuality quality,
    required bool reduceMotion,
    required bool batterySaver,
    bool lagging = false,
  }) {
    if (style == ArtworkGlowStyle.off) return off;
    final intensity = style == ArtworkGlowStyle.subtle ? 0.55 : 1.0;
    final effective = switch (quality) {
      AnimationQuality.auto when batterySaver => AnimationQuality.batterySaver,
      AnimationQuality.auto when lagging => AnimationQuality.balanced,
      AnimationQuality.auto => AnimationQuality.high,
      _ => quality,
    };
    final still = reduceMotion || effective == AnimationQuality.batterySaver;
    final balanced = effective != AnimationQuality.high;
    return GlowRendering(
      visible: true,
      animated: !still,
      fields: balanced ? 3 : 5,
      frameInterval: Duration(milliseconds: balanced ? 50 : 33),
      intensity: intensity,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlowRendering &&
      other.visible == visible &&
      other.animated == animated &&
      other.fields == fields &&
      other.frameInterval == frameInterval &&
      other.intensity == intensity;

  @override
  int get hashCode =>
      Object.hash(visible, animated, fields, frameInterval, intensity);
}
