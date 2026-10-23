import 'dart:async';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';

/// A restrained palette taken from album artwork: a dark [scrim] that keeps
/// white text readable and a brighter [accent] for progress and lyrics.
@immutable
class ArtworkPalette {
  final Color scrim;
  final Color accent;

  const ArtworkPalette({required this.scrim, required this.accent});

  static const fallback = ArtworkPalette(
    scrim: Color(0xFF15171C),
    accent: Color(0xFF6FB3FF),
  );

  /// Builds the palette from RGBA pixels of a small thumbnail.
  factory ArtworkPalette.fromPixels(Uint8List rgba) {
    var r = 0, g = 0, b = 0, count = 0;
    HSLColor? vivid;
    var vividScore = 0.0;
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
      final score =
          hsl.saturation * (1 - (hsl.lightness - 0.5).abs() * 2).clamp(0, 1);
      if (score > vividScore) {
        vividScore = score;
        vivid = hsl;
      }
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
    return ArtworkPalette(scrim: scrim, accent: accent);
  }

  /// WCAG contrast ratio of white text on [scrim]; kept at 4.5 or more.
  double get whiteTextContrast => 1.05 / (scrim.computeLuminance() + 0.05);
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
    // Decoding a 24 px thumbnail keeps this off the interaction path.
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
