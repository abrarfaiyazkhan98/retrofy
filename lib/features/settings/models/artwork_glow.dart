import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:flutter/widgets.dart';

/// How strongly the artwork's colours glow around it.
enum ArtworkGlowStyle {
  off,
  subtle,
  dynamic;

  static ArtworkGlowStyle fromName(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => dynamic);

  String title(BuildContext context) => switch (this) {
    off => context.localization.artworkGlowOffTitle,
    subtle => context.localization.artworkGlowSubtleTitle,
    dynamic => context.localization.artworkGlowDynamicTitle,
  };
}

/// How much animation work the glow may do.
enum AnimationQuality {
  auto,
  high,
  balanced,
  batterySaver;

  static AnimationQuality fromName(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => auto);

  String title(BuildContext context) => switch (this) {
    auto => context.localization.animationQualityAutoTitle,
    high => context.localization.animationQualityHighTitle,
    balanced => context.localization.animationQualityBalancedTitle,
    batterySaver => context.localization.animationQualityBatterySaverTitle,
  };
}
