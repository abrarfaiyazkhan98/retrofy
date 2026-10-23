import 'dart:async';

import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Snapshot from the Spotify app. Position is extrapolated between events,
/// since App Remote only reports on change rather than on a timer.
class SpotifyPlayerState {
  final String? trackUri;
  final String? trackName;
  final List<String> artists;
  final String? albumName;
  final String? imageUri;
  final int durationMs;
  final int positionMs;
  final bool isPaused;
  final double playbackSpeed;
  final bool isShuffling;
  final int repeatMode;
  final bool isEpisode;
  final DateTime receivedAt;

  const SpotifyPlayerState({
    this.trackUri,
    this.trackName,
    this.artists = const [],
    this.albumName,
    this.imageUri,
    this.durationMs = 0,
    this.positionMs = 0,
    this.isPaused = true,
    this.playbackSpeed = 1,
    this.isShuffling = false,
    this.repeatMode = 0,
    this.isEpisode = false,
    required this.receivedAt,
  });

  static const repeatOff = 0;
  static const repeatOne = 1;
  static const repeatAll = 2;

  factory SpotifyPlayerState.fromMap(Map<Object?, Object?> map, DateTime now) {
    int asInt(Object? value) => value is num ? value.toInt() : 0;
    return SpotifyPlayerState(
      trackUri: map['trackUri'] as String?,
      trackName: map['trackName'] as String?,
      artists: [
        for (final artist in map['artists'] as List? ?? const [])
          if (artist is String) artist,
      ],
      albumName: map['albumName'] as String?,
      imageUri: map['imageUri'] as String?,
      durationMs: asInt(map['durationMs']),
      positionMs: asInt(map['positionMs']),
      isPaused: map['isPaused'] != false,
      playbackSpeed: (map['playbackSpeed'] as num?)?.toDouble() ?? 1,
      isShuffling: map['isShuffling'] == true,
      repeatMode: asInt(map['repeatMode']),
      isEpisode: map['isEpisode'] == true,
      receivedAt: now,
    );
  }

  Duration positionAt(DateTime now) {
    var position = positionMs;
    if (!isPaused) {
      final speed = playbackSpeed > 0 ? playbackSpeed : 1;
      position += (now.difference(receivedAt).inMilliseconds * speed).round();
    }
    if (durationMs > 0) position = position.clamp(0, durationMs);
    return Duration(milliseconds: position < 0 ? 0 : position);
  }
}

sealed class SpotifyRemoteEvent {
  const SpotifyRemoteEvent();
}

class SpotifyPlayerStateEvent extends SpotifyRemoteEvent {
  final SpotifyPlayerState state;
  const SpotifyPlayerStateEvent(this.state);
}

class SpotifyCapabilitiesEvent extends SpotifyRemoteEvent {
  final bool canPlayOnDemand;
  const SpotifyCapabilitiesEvent({required this.canPlayOnDemand});
}

class SpotifyDisconnectedEvent extends SpotifyRemoteEvent {
  final String code;
  const SpotifyDisconnectedEvent(this.code);
}

/// Controls the installed Spotify app. Audio is decoded and played entirely
/// by Spotify; Retrofy only sends commands and mirrors its state.
abstract class SpotifyRemote {
  Stream<SpotifyRemoteEvent> get events;
  Future<bool> isSpotifyInstalled();
  Future<void> connect({
    required String clientId,
    required String redirectUri,
    required String appRemoteRedirectUri,
  });
  Future<void> disconnect();
  Future<void> play(String uri);
  Future<void> skipToIndex(String contextUri, int index);
  Future<void> resume();
  Future<void> pause();
  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> seekTo(Duration position);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeat(int mode);
}

class MethodChannelSpotifyRemote implements SpotifyRemote {
  static const _methods = MethodChannel('retrofy/spotify_remote');
  static const _eventChannel = EventChannel('retrofy/spotify_remote/events');
  final DateTime Function() _now;

  MethodChannelSpotifyRemote({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  @override
  late final Stream<SpotifyRemoteEvent> events = _eventChannel
      .receiveBroadcastStream()
      .map((event) {
        final map = event as Map<Object?, Object?>;
        return switch (map['type']) {
          'playerState' => SpotifyPlayerStateEvent(
            SpotifyPlayerState.fromMap(map, _now()),
          ),
          'capabilities' => SpotifyCapabilitiesEvent(
            canPlayOnDemand: map['canPlayOnDemand'] == true,
          ),
          _ => SpotifyDisconnectedEvent(map['code'] as String? ?? 'unknown'),
        };
      })
      .asBroadcastStream();

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw SpotifyException(error.code);
    } on MissingPluginException {
      throw const SpotifyException('unsupported_platform');
    }
  }

  @override
  Future<bool> isSpotifyInstalled() async =>
      await _call<bool>('isSpotifyInstalled') ?? false;

  @override
  Future<void> connect({
    required String clientId,
    required String redirectUri,
    required String appRemoteRedirectUri,
  }) => _call<void>('connect', {
    'clientId': clientId,
    'redirectUri': redirectUri,
    'appRemoteRedirectUri': appRemoteRedirectUri,
  });

  @override
  Future<void> disconnect() => _call<void>('disconnect');

  @override
  Future<void> play(String uri) => _call<void>('play', {'uri': uri});

  @override
  Future<void> skipToIndex(String contextUri, int index) =>
      _call<void>('skipToIndex', {'uri': contextUri, 'index': index});

  @override
  Future<void> resume() => _call<void>('resume');

  @override
  Future<void> pause() => _call<void>('pause');

  @override
  Future<void> skipNext() => _call<void>('skipNext');

  @override
  Future<void> skipPrevious() => _call<void>('skipPrevious');

  @override
  Future<void> seekTo(Duration position) =>
      _call<void>('seekTo', {'positionMs': position.inMilliseconds});

  @override
  Future<void> setShuffle(bool enabled) =>
      _call<void>('setShuffle', {'enabled': enabled});

  @override
  Future<void> setRepeat(int mode) => _call<void>('setRepeat', {'mode': mode});
}

/// Delivers the OAuth redirect captured by MainActivity's intent filter,
/// including one that cold-started the app after the login tab.
class SpotifyRedirectChannel {
  static const _channel = MethodChannel('retrofy/spotify_auth');
  final _redirects = StreamController<Uri>.broadcast();

  SpotifyRedirectChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'redirect' && call.arguments is String) {
        final uri = Uri.tryParse(call.arguments as String);
        // Only the address is logged; the query holds the one-time code.
        debugPrint('Spotify redirect received: ${uri?.replace(query: '')}');
        if (uri != null) _redirects.add(uri);
      }
    });
  }

  Stream<Uri> get redirects => _redirects.stream;

  Future<Uri?> takePending() async {
    try {
      final value = await _channel.invokeMethod<String>('takePendingRedirect');
      if (value != null) debugPrint('Spotify redirect pending at startup');
      return value == null ? null : Uri.tryParse(value);
    } on MissingPluginException {
      return null;
    }
  }
}
