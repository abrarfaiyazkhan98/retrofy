import 'dart:async';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';

/// A restrained palette taken from album artwork.
///
/// [primary] and [secondary] are the cover's two strongest colour families,
/// toned down for large glowing fields; [accent] is its most vivid colour for
/// progress and lyrics; [scrim] is a dark tint of the whole cover that keeps
/// white text readable and serves as the atmospheric base.
@immutable
class ArtworkPalette {
  final Color scrim;
  final Color accent;
  final Color primary;
  final Color secondary;

  const ArtworkPalette({
    required this.scrim,
    required this.accent,
    required this.primary,
    required this.secondary,
  });

  static const fallback = ArtworkPalette(
    scrim: Color(0xFF15171C),
    accent: Color(0xFF6FB3FF),
    primary: Color(0xFF2E4A6E),
    secondary: Color(0xFF4A3A6A),
  );

  /// Dark base under the glow; the same colour as [scrim].
  Color get base => scrim;

  /// Text and icon colour over [base].
  Color get foreground => const Color(0xFFFFFFFF);

  /// Background of the Now Playing information panel under the cover: the
  /// cover's own dark tone, restrained so it never looks neon and white text
  /// always keeps a contrast of 7:1 or more.
  Color get panel {
    final hsl = HSLColor.fromColor(scrim);
    return hsl
        .withSaturation(hsl.saturation.clamp(0, 0.32))
        .withLightness(hsl.lightness.clamp(0.13, 0.18))
        .toColor();
  }

  /// Builds the palette from RGBA pixels of a small thumbnail.
  factory ArtworkPalette.fromPixels(Uint8List rgba) {
    var r = 0, g = 0, b = 0, count = 0;
    HSLColor? vivid;
    var vividScore = 0.0;
    // Chromatic pixels grouped into 12 hue families of 30 degrees.
    final weights = List<double>.filled(_hueFamilies, 0);
    final sums = List<List<double>>.generate(_hueFamilies, (_) => [0, 0, 0]);
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) continue;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      count++;
      final hsl = HSLColor.fromColor(
        Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]),
      );
      // Prefer saturated mid-tones; near-black and near-white make poor
      // accents.
      final midTone = (1 - (hsl.lightness - 0.5).abs() * 2).clamp(0.0, 1.0);
      final score = hsl.saturation * midTone;
      if (score > vividScore) {
        vividScore = score;
        vivid = hsl;
      }
      if (hsl.saturation < 0.18 || midTone < 0.2) continue;
      final family = (hsl.hue / 360 * _hueFamilies).floor() % _hueFamilies;
      final weight = 0.5 + score;
      weights[family] += weight;
      sums[family][0] += rgba[i] * weight;
      sums[family][1] += rgba[i + 1] * weight;
      sums[family][2] += rgba[i + 2] * weight;
    }
    if (count == 0) return fallback;
    final average = HSLColor.fromColor(
      Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count),
    );
    final scrim = average
        .withSaturation(average.saturation.clamp(0, 0.45))
        .withLightness(average.lightness.clamp(0.06, 0.16))
        .toColor();
    final accent = vivid == null || vividScore < 0.15
        ? fallback.accent
        : vivid
              .withSaturation(vivid.saturation.clamp(0.35, 0.8))
              .withLightness(0.62)
              .toColor();

    HSLColor familyColor(int family) {
      final w = weights[family];
      return HSLColor.fromColor(
        Color.fromARGB(
          255,
          (sums[family][0] / w).round(),
          (sums[family][1] / w).round(),
          (sums[family][2] / w).round(),
        ),
      );
    }

    final ranked = [
      for (var i = 0; i < _hueFamilies; i++)
        if (weights[i] > 0) i,
    ]..sort((a, c) => weights[c].compareTo(weights[a]));
    // A cover counts as colourful once a tenth of it is one colour family;
    // otherwise its glow stays in the cover's own near-neutral tones.
    final colourful = ranked.isNotEmpty && weights[ranked.first] >= count * 0.1;
    final primary = colourful ? familyColor(ranked.first) : average;
    HSLColor? second;
    if (colourful) {
      for (final family in ranked.skip(1)) {
        if (weights[family] < weights[ranked.first] * 0.25) break;
        final candidate = familyColor(family);
        if (_hueDistance(candidate.hue, primary.hue) >= 40) {
          second = candidate;
          break;
        }
      }
    }
    // Single-colour covers get a neighbouring shade instead of a second hue.
    second ??= primary
        .withHue((primary.hue + 24) % 360)
        .withLightness((primary.lightness - 0.08).clamp(0, 1));
    return ArtworkPalette(
      scrim: scrim,
      accent: accent,
      primary: _glowTone(primary),
      secondary: _glowTone(second),
    );
  }

  static const _hueFamilies = 12;

  static double _hueDistance(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Glow fields sit behind white text: never neon, never near-white.
  static Color _glowTone(HSLColor color) => color
      .withSaturation(color.saturation.clamp(0, 0.7))
      .withLightness(color.lightness.clamp(0.24, 0.48))
      .toColor();

  /// WCAG contrast ratio of white text on [scrim]; kept at 4.5 or more.
  double get whiteTextContrast => 1.05 / (scrim.computeLuminance() + 0.05);

  static ArtworkPalette lerp(ArtworkPalette a, ArtworkPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    return ArtworkPalette(
      scrim: Color.lerp(a.scrim, b.scrim, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      primary: Color.lerp(a.primary, b.primary, t)!,
      secondary: Color.lerp(a.secondary, b.secondary, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ArtworkPalette &&
      other.scrim == scrim &&
      other.accent == accent &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(scrim, accent, primary, secondary);
}

/// Palettes are computed once per artwork and kept for recently shown
/// covers only.
class ArtworkPaletteCache {
  static const _capacity = 48;
  static final _palettes = <Object, Future<ArtworkPalette>>{};

  /// [key] identifies the artwork (its path); image providers built from
  /// downloaded bytes do not compare equal across rebuilds.
  static Future<ArtworkPalette> of(Object key, ImageProvider provider) {
    final cached = _palettes.remove(key);
    final palette = cached ?? _extract(provider);
    // Map literals keep insertion order, so the first key is the oldest.
    _palettes[key] = palette;
    if (_palettes.length > _capacity) {
      _palettes.remove(_palettes.keys.first)?.ignore();
    }
    return palette;
  }

  static Future<ArtworkPalette> _extract(ImageProvider provider) {
    final completer = Completer<ArtworkPalette>();
    // The engine decodes a 24 px thumbnail off the UI thread; reading its
    // 576 pixels here costs well under a millisecond.
    final stream = ResizeImage(
      provider,
      width: 24,
      height: 24,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, _) async {
        stream.removeListener(listener);
        try {
          final data = await image.image.toByteData();
          completer.complete(
            data == null
                ? ArtworkPalette.fallback
                : ArtworkPalette.fromPixels(data.buffer.asUint8List()),
          );
        } catch (_) {
          completer.complete(ArtworkPalette.fallback);
        } finally {
          image.dispose();
        }
      },
      onError: (_, _) {
        stream.removeListener(listener);
        completer.complete(ArtworkPalette.fallback);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @visibleForTesting
  static void clear() => _palettes.clear();
}
