import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final spotifyRemoteProvider = Provider<SpotifyRemote>(
  (_) => MethodChannelSpotifyRemote(),
);

enum SpotifyConnection { disconnected, connecting, connected }

class SpotifyPlaybackState {
  final SpotifyConnection connection;
  final SpotifyPlayerState? player;

  /// Null until the Spotify app reports it. False means the account cannot
  /// pick individual tracks (not Premium).
  final bool? canPlayOnDemand;
  final String? error;

  const SpotifyPlaybackState({
    this.connection = SpotifyConnection.disconnected,
    this.player,
    this.canPlayOnDemand,
    this.error,
  });

  SpotifyPlaybackState copyWith({
    SpotifyConnection? connection,
    SpotifyPlayerState? player,
    bool? canPlayOnDemand,
    String? error,
    bool clearError = false,
  }) => SpotifyPlaybackState(
    connection: connection ?? this.connection,
    player: player ?? this.player,
    canPlayOnDemand: canPlayOnDemand ?? this.canPlayOnDemand,
    error: clearError ? null : error ?? this.error,
  );
}

final spotifyPlaybackControllerProvider =
    NotifierProvider<SpotifyPlaybackController, SpotifyPlaybackState>(
      SpotifyPlaybackController.new,
    );

class SpotifyPlaybackController extends Notifier<SpotifyPlaybackState> {
  Future<void>? _connecting;
  Timer? _ticker;
  // The progress ticker only runs while something (progress bar, lyrics)
  // listens, so no timer wakes the app in the background or on menus.
  late final _playbackStates = StreamController<PlaybackState>.broadcast(
    onListen: _emit,
    onCancel: _stopTicker,
  );

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Progress is only drawn while Retrofy is in the foreground.
  bool _appVisible = true;

  SpotifyRemote get _remote => ref.read(spotifyRemoteProvider);
  DateTime _now() => ref.read(spotifyClockProvider)();

  @override
  SpotifyPlaybackState build() {
    final subscription = _remote.events.listen(_onEvent, onError: (_) {});
    // In the background the ticker stops; on return the interpolated
    // position is emitted at once, so progress is correct immediately.
    final lifecycle = AppLifecycleListener(
      onShow: () {
        _appVisible = true;
        _emit();
      },
      onHide: () {
        _appVisible = false;
        _stopTicker();
      },
    );
    ref.onDispose(lifecycle.dispose);
    ref.onDispose(() {
      _ticker?.cancel();
      unawaited(subscription.cancel());
      unawaited(_playbackStates.close());
    });
    ref.listen(
      spotifyAuthControllerProvider.select((value) => value.value?.signedIn),
      (previous, signedIn) {
        if (previous == true && signedIn != true) unawaited(disconnect());
      },
    );
    return const SpotifyPlaybackState();
  }

  /// Position stream for the Now Playing progress bar. Emits on every Spotify
  /// event and twice a second while playing, interpolating between events.
  Stream<PlaybackState> get playbackStates => _playbackStates.stream;

  Duration get position => state.player?.positionAt(_now()) ?? Duration.zero;

  PlaybackState get currentPlaybackState {
    final player = state.player;
    return PlaybackState(
      processingState: switch (state.connection) {
        SpotifyConnection.connecting => AudioProcessingState.loading,
        SpotifyConnection.connected => AudioProcessingState.ready,
        SpotifyConnection.disconnected =>
          state.error == null
              ? AudioProcessingState.idle
              : AudioProcessingState.error,
      },
      playing: player != null && !player.isPaused,
      updatePosition: position,
      speed: player?.playbackSpeed ?? 1,
      errorMessage: state.error,
      shuffleMode: player?.isShuffling == true
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: switch (player?.repeatMode) {
        SpotifyPlayerState.repeatOne => AudioServiceRepeatMode.one,
        SpotifyPlayerState.repeatAll => AudioServiceRepeatMode.all,
        _ => AudioServiceRepeatMode.none,
      },
    );
  }

  void _emit() {
    if (_playbackStates.isClosed) return;
    _playbackStates.add(currentPlaybackState);
    final playing = state.player?.isPaused == false;
    if (playing &&
        _appVisible &&
        _playbackStates.hasListener &&
        _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!_playbackStates.isClosed) {
          _playbackStates.add(currentPlaybackState);
        }
      });
    } else if (!playing || !_appVisible || !_playbackStates.hasListener) {
      _stopTicker();
    }
  }

  void _onEvent(SpotifyRemoteEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case SpotifyPlayerStateEvent(:final state):
        this.state = this.state.copyWith(
          connection: SpotifyConnection.connected,
          player: state,
          clearError: true,
        );
      case SpotifyCapabilitiesEvent(:final canPlayOnDemand):
        state = state.copyWith(canPlayOnDemand: canPlayOnDemand);
      case SpotifyDisconnectedEvent(:final code):
        _connecting = null;
        state = SpotifyPlaybackState(
          player: state.player == null
              ? null
              : SpotifyPlayerState(
                  trackUri: state.player!.trackUri,
                  trackName: state.player!.trackName,
                  artists: state.player!.artists,
                  artistUris: state.player!.artistUris,
                  albumName: state.player!.albumName,
                  imageUri: state.player!.imageUri,
                  durationMs: state.player!.durationMs,
                  positionMs: state.player!.positionAt(_now()).inMilliseconds,
                  isShuffling: state.player!.isShuffling,
                  repeatMode: state.player!.repeatMode,
                  receivedAt: _now(),
                ),
          canPlayOnDemand: state.canPlayOnDemand,
          error: code,
        );
    }
    _emit();
  }

  /// Connects to the installed Spotify app, which asks the user to approve
  /// Retrofy the first time. Concurrent callers share one attempt.
  Future<void> ensureConnected() {
    if (state.connection == SpotifyConnection.connected) return Future.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final config = ref.read(spotifyConfigProvider);
    if (!config.isConfigured) throw const SpotifyException('not_configured');
    state = state.copyWith(
      connection: SpotifyConnection.connecting,
      clearError: true,
    );
    _emit();
    try {
      if (!await _remote.isSpotifyInstalled()) {
        throw const SpotifyException('not_installed');
      }
      await _remote
          .connect(
            clientId: config.clientId,
            redirectUri: config.redirectUri,
            appRemoteRedirectUri: SpotifyConfig.appRemoteRedirectUri,
          )
          // Long enough for the first-time approval screen in Spotify; the
          // pending play request continues once the connection succeeds.
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () => throw const SpotifyException('timeout'),
          );
      if (!ref.mounted) return;
      state = state.copyWith(connection: SpotifyConnection.connected);
      _emit();
    } on SpotifyException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          connection: SpotifyConnection.disconnected,
          error: error.code,
        );
        _emit();
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      await _remote.disconnect();
    } catch (_) {}
    if (ref.mounted) {
      state = const SpotifyPlaybackState();
      _emit();
    }
  }

  /// Runs [command] on a live connection. A connection the Spotify app
  /// dropped in the background is re-established once before giving up.
  Future<void> _command(Future<void> Function(SpotifyRemote) command) async {
    await ensureConnected();
    try {
      await command(_remote);
    } on SpotifyException catch (error) {
      if (error.code != 'disconnected' && error.code != 'not_connected') {
        rethrow;
      }
      if (ref.mounted) {
        state = state.copyWith(connection: SpotifyConnection.disconnected);
      }
      await ensureConnected();
      await command(_remote);
    }
  }

  /// Track choice needs on-demand playback, i.e. Spotify Premium.
  void _requireOnDemand() {
    if (state.canPlayOnDemand == false) {
      throw const SpotifyException('premium_required');
    }
  }

  /// Starts [contextUri] (album or playlist) at [index] so Spotify keeps
  /// playing the rest of that context afterwards.
  Future<void> playContext(String contextUri, int index) => _command((remote) {
    _requireOnDemand();
    return remote.skipToIndex(contextUri, index);
  });

  Future<void> playUri(String uri) => _command((remote) {
    if (uri.startsWith('spotify:track:')) _requireOnDemand();
    return remote.play(uri);
  });

  /// The moment a play request is sent and the track playing then, for
  /// [confirmTrack].
  ({DateTime since, String? before}) get requestMark =>
      (since: _now(), before: state.player?.trackUri);

  /// Waits for Spotify to settle on a track after the request marked by
  /// [mark] and returns it, or null if Spotify reports no track at all.
  ///
  /// A report of [trackUri] confirms it at once, unless [trackUri] was
  /// already playing: Spotify may report the old track once more before
  /// switching, so then, like any other track, it only counts once nothing
  /// changes for [grace]. If Spotify reports nothing new before [timeout],
  /// whatever is playing is the answer, so an ignored request is noticed.
  Future<String?> confirmTrack(
    String trackUri, {
    required ({DateTime since, String? before}) mark,
    Duration timeout = const Duration(seconds: 4),
    Duration grace = const Duration(seconds: 1),
  }) {
    final result = Completer<String?>();
    Timer? settle;
    void finish(String? uri) {
      if (!result.isCompleted) result.complete(uri);
    }

    void reported(String? uri) {
      if (uri == trackUri && uri != mark.before) return finish(uri);
      settle?.cancel();
      settle = Timer(grace, () => finish(uri));
    }

    final player = state.player;
    if (player != null && !player.receivedAt.isBefore(mark.since)) {
      reported(player.trackUri);
    }
    final subscription = _remote.events.listen((event) {
      if (event is SpotifyPlayerStateEvent) reported(event.state.trackUri);
    }, onDone: () => finish(state.player?.trackUri));
    final deadline = Timer(timeout, () => finish(state.player?.trackUri));
    return result.future.whenComplete(() {
      settle?.cancel();
      deadline.cancel();
      unawaited(subscription.cancel());
    });
  }

  Future<void> resume() => _command((remote) => remote.resume());

  Future<void> pause() async {
    // Nothing to pause when Spotify is not connected; avoid launching it.
    if (state.connection != SpotifyConnection.connected) return;
    await _command((remote) => remote.pause());
  }

  Future<void> togglePlayback() =>
      state.player?.isPaused == false ? pause() : resume();

  Future<void> skipNext() => _command((remote) => remote.skipNext());

  Future<void> skipPrevious() => _command((remote) => remote.skipPrevious());

  Future<void> seekTo(Duration position) =>
      _command((remote) => remote.seekTo(position));

  Future<void> setShuffle(bool enabled) =>
      _command((remote) => remote.setShuffle(enabled));

  Future<void> setRepeat(int mode) =>
      _command((remote) => remote.setRepeat(mode));
}
