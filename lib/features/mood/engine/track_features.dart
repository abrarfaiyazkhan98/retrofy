import 'package:classipod/core/spotify/spotify_api_client.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:flutter/foundation.dart';

/// Measured audio features of one track. Values are only ever taken from a
/// metadata provider; Retrofy never estimates or invents them.
@immutable
class TrackFeatures {
  final double? tempo;
  final double? energy;
  final double? valence;

  const TrackFeatures({this.tempo, this.energy, this.valence});

  static TrackFeatures? fromJson(Object? json) {
    if (json is! Map) return null;
    double? number(Object? value) => value is num ? value.toDouble() : null;
    final tempo = number(json['tempo']);
    return TrackFeatures(
      // Spotify reports 0 when it could not detect a tempo.
      tempo: tempo == null || tempo <= 0 ? null : tempo,
      energy: number(json['energy']),
      valence: number(json['valence']),
    );
  }
}

/// Features for a set of tracks, and whether the provider could supply any.
@immutable
class TrackFeatureResult {
  final bool available;
  final Map<String, TrackFeatures> byTrackUri;

  const TrackFeatureResult(this.byTrackUri) : available = true;

  const TrackFeatureResult.unavailable()
    : available = false,
      byTrackUri = const {};
}

/// Where tempo, energy and valence come from. A provider abstraction so a
/// licensed metadata service or local analysis of the user's own files can
/// replace Spotify's without touching the engine.
abstract class TrackFeatureSource {
  Future<TrackFeatureResult> featuresFor(List<String> trackUris);
}

/// Spotify's audio-features endpoint. Spotify closed it to apps created
/// after 27 November 2024, so the first 403 or 404 switches the source off
/// for the session instead of retrying on every request.
class SpotifyAudioFeatureSource implements TrackFeatureSource {
  final SpotifyApiClient _api;
  bool? _available;

  SpotifyAudioFeatureSource(this._api);

  /// Spotify accepts at most 100 IDs per request.
  static const _batch = 100;

  @override
  Future<TrackFeatureResult> featuresFor(List<String> trackUris) async {
    if (_available == false || trackUris.isEmpty) {
      return const TrackFeatureResult.unavailable();
    }
    const prefix = 'spotify:track:';
    final ids = [
      for (final uri in trackUris)
        if (uri.startsWith(prefix)) uri.substring(prefix.length),
    ];
    final features = <String, TrackFeatures>{};
    try {
      for (var start = 0; start < ids.length; start += _batch) {
        final end = start + _batch > ids.length ? ids.length : start + _batch;
        for (final item in await _api.audioFeatures(ids.sublist(start, end))) {
          final id = item is Map ? item['id'] : null;
          final parsed = TrackFeatures.fromJson(item);
          if (id is String && parsed != null) {
            features['$prefix$id'] = parsed;
          }
        }
      }
    } on SpotifyException catch (error) {
      if (error.code == 'forbidden' || error.code == 'not_found') {
        debugPrint('Spotify audio features are not available to Retrofy');
        _available = false;
      }
      return const TrackFeatureResult.unavailable();
    }
    _available = true;
    return TrackFeatureResult(features);
  }
}
