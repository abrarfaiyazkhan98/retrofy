import 'dart:async';

import 'package:classipod/core/spotify/spotify_api_client.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/core/spotify/spotify_token_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final spotifyConfigProvider = Provider<SpotifyConfig>(
  (_) => const SpotifyConfig.fromEnvironment(),
);
final spotifyClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
final spotifyTokenStoreProvider = Provider<SpotifyTokenStore>(
  (_) => const SecureSpotifyTokenStore(),
);
final spotifyAuthClientProvider = Provider<SpotifyAuthClient>((ref) {
  final client = SpotifyAuthClient(
    ref.watch(spotifyConfigProvider),
    now: ref.watch(spotifyClockProvider),
  );
  ref.onDispose(client.close);
  return client;
});
final spotifyRedirectChannelProvider = Provider<SpotifyRedirectChannel>(
  (_) => SpotifyRedirectChannel(),
);

/// Opens the authorization page in the user's browser (a Custom Tab or the
/// default browser), never an embedded web view, so Retrofy never sees the
/// Spotify password.
final spotifyBrowserLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

enum SpotifyAuthStatus { notConfigured, signedOut, signingIn, signedIn }

class SpotifyAuthState {
  final SpotifyAuthStatus status;
  final SpotifyProfile? profile;
  final String? error;

  const SpotifyAuthState(this.status, {this.profile, this.error});

  bool get signedIn => status == SpotifyAuthStatus.signedIn;
}

final spotifyAuthControllerProvider =
    AsyncNotifierProvider<SpotifyAuthController, SpotifyAuthState>(
      SpotifyAuthController.new,
    );

class SpotifyAuthController extends AsyncNotifier<SpotifyAuthState> {
  SpotifyTokens? _tokens;
  Future<SpotifyTokens>? _refreshing;
  Timer? _cancelTimer;

  SpotifyTokenStore get _store => ref.read(spotifyTokenStoreProvider);
  SpotifyConfig get _config => ref.read(spotifyConfigProvider);
  DateTime _now() => ref.read(spotifyClockProvider)();

  @override
  Future<SpotifyAuthState> build() async {
    if (!_config.isConfigured) {
      return const SpotifyAuthState(SpotifyAuthStatus.notConfigured);
    }
    final channel = ref.read(spotifyRedirectChannelProvider);
    final subscription = channel.redirects.listen(
      (uri) => unawaited(_completeRedirect(uri)),
    );
    final lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(() {
      _cancelTimer?.cancel();
      lifecycle.dispose();
      unawaited(subscription.cancel());
    });

    // The saved session loads first so a redirect left over from an earlier
    // process (e.g. after a crash) can never replace it with an error.
    try {
      _tokens = await _store.readTokens();
    } catch (_) {
      _tokens = null;
    }
    final pendingRedirect = await channel.takePending();
    if (pendingRedirect != null) {
      final completed = await _complete(pendingRedirect);
      if (completed != null) return completed;
    }
    if (_tokens == null) {
      return const SpotifyAuthState(SpotifyAuthStatus.signedOut);
    }
    unawaited(Future(_loadProfile));
    return const SpotifyAuthState(SpotifyAuthStatus.signedIn);
  }

  SpotifyAuthState get _current =>
      state.value ?? const SpotifyAuthState(SpotifyAuthStatus.signedOut);

  Future<void> signIn() async {
    if (!_config.isConfigured) return;
    final session = SpotifyPkceSession.generate(now: _now());
    try {
      await _store.writePending(session);
    } catch (_) {
      state = const AsyncData(
        SpotifyAuthState(SpotifyAuthStatus.signedOut, error: 'storage'),
      );
      return;
    }
    state = const AsyncData(SpotifyAuthState(SpotifyAuthStatus.signingIn));
    final opened = await ref.read(spotifyBrowserLauncherProvider)(
      session.authorizeUri(_config),
    );
    if (!opened && ref.mounted) {
      await _store.clearPending();
      state = const AsyncData(
        SpotifyAuthState(SpotifyAuthStatus.signedOut, error: 'browser'),
      );
    }
  }

  /// Returning from the browser without a redirect means the user closed it.
  void _onResume() {
    if (_current.status != SpotifyAuthStatus.signingIn) return;
    _cancelTimer?.cancel();
    _cancelTimer = Timer(const Duration(seconds: 3), () {
      if (ref.mounted && _current.status == SpotifyAuthStatus.signingIn) {
        unawaited(_store.clearPending().catchError((Object _) {}));
        state = const AsyncData(SpotifyAuthState(SpotifyAuthStatus.signedOut));
      }
    });
  }

  Future<void> _completeRedirect(Uri uri) async {
    _cancelTimer?.cancel();
    final completed = await _complete(uri);
    if (completed != null && ref.mounted) state = AsyncData(completed);
  }

  /// Returns null when [uri] is not ours to handle.
  Future<SpotifyAuthState?> _complete(Uri uri) async {
    final config = _config;
    final expected = Uri.parse(config.redirectUri);
    if (uri.scheme != expected.scheme || uri.host != expected.host) {
      return null;
    }
    SpotifyPkceSession? session;
    try {
      session = await _store.readPending();
      await _store.clearPending();
    } catch (_) {}
    // Without a pending attempt the redirect is not ours to act on: it was
    // already consumed, or it outlived the process that started it.
    if (session == null) {
      debugPrint('Spotify redirect ignored: no pending sign-in');
      return null;
    }
    if (session.expired(_now())) {
      debugPrint('Spotify sign-in failed: sign-in expired');
      return const SpotifyAuthState(
        SpotifyAuthStatus.signedOut,
        error: 'state_mismatch',
      );
    }
    try {
      final code = session.codeFrom(uri, config);
      final tokens = await ref
          .read(spotifyAuthClientProvider)
          .exchangeCode(code, session.verifier);
      await _store.writeTokens(tokens);
      _tokens = tokens;
    } on SpotifyException catch (error) {
      debugPrint('Spotify sign-in failed: ${error.code}');
      return SpotifyAuthState(SpotifyAuthStatus.signedOut, error: error.code);
    } catch (error) {
      debugPrint('Spotify sign-in failed: ${error.runtimeType}');
      return const SpotifyAuthState(
        SpotifyAuthStatus.signedOut,
        error: 'storage',
      );
    }
    unawaited(Future(_loadProfile));
    return const SpotifyAuthState(SpotifyAuthStatus.signedIn);
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ref.read(spotifyApiProvider).me();
      if (ref.mounted && _current.signedIn) {
        state = AsyncData(
          SpotifyAuthState(SpotifyAuthStatus.signedIn, profile: profile),
        );
      }
    } catch (_) {
      // The profile is cosmetic; offline sign-in state stays valid.
    }
  }

  /// Valid access token for the Web API, refreshing when it is close to
  /// expiry. Concurrent callers share a single refresh request.
  Future<String> accessToken({bool forceRefresh = false}) async {
    if (!ref.mounted) throw const SpotifyException('signin');
    var tokens = _tokens;
    if (tokens == null) throw const SpotifyException('signin');
    if (forceRefresh || tokens.expired(_now())) {
      tokens = await (_refreshing ??= _refresh(tokens).whenComplete(() {
        _refreshing = null;
      }));
    }
    return tokens.accessToken;
  }

  Future<SpotifyTokens> _refresh(SpotifyTokens tokens) async {
    try {
      final refreshed = await ref
          .read(spotifyAuthClientProvider)
          .refresh(tokens);
      _tokens = refreshed;
      await _store.writeTokens(refreshed);
      return refreshed;
    } on SpotifyException catch (error) {
      if (error.code == 'session_expired') await _signOut('session_expired');
      rethrow;
    }
  }

  /// Spotify offers no token revocation endpoint for PKCE clients, so sign
  /// out deletes every stored token; access can be removed entirely at
  /// spotify.com/account/apps.
  Future<void> signOut() => _signOut(null);

  Future<void> _signOut(String? reason) async {
    _tokens = null;
    try {
      await _store.clear();
    } catch (_) {}
    if (ref.mounted) {
      state = AsyncData(
        SpotifyAuthState(
          _config.isConfigured
              ? SpotifyAuthStatus.signedOut
              : SpotifyAuthStatus.notConfigured,
          error: reason,
        ),
      );
    }
  }
}

final spotifyApiProvider = Provider<SpotifyApiClient>((ref) {
  final client = SpotifyApiClient(
    ({forceRefresh = false}) => ref
        .read(spotifyAuthControllerProvider.notifier)
        .accessToken(forceRefresh: forceRefresh),
  );
  ref.onDispose(client.close);
  return client;
});
