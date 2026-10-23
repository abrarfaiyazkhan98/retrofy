import 'dart:async';
import 'dart:convert';

import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/core/spotify/spotify_token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStore implements SpotifyTokenStore {
  SpotifyTokens? tokens;
  SpotifyPkceSession? pending;

  @override
  Future<SpotifyTokens?> readTokens() async => tokens;
  @override
  Future<void> writeTokens(SpotifyTokens value) async => tokens = value;
  @override
  Future<SpotifyPkceSession?> readPending() async => pending;
  @override
  Future<void> writePending(SpotifyPkceSession value) async => pending = value;
  @override
  Future<void> clearPending() async => pending = null;
  @override
  Future<void> clear() async {
    tokens = null;
    pending = null;
  }
}

class FakeRedirects extends SpotifyRedirectChannel {
  final controller = StreamController<Uri>.broadcast();
  Uri? pendingRedirect;

  @override
  Stream<Uri> get redirects => controller.stream;

  @override
  Future<Uri?> takePending() async {
    final value = pendingRedirect;
    pendingRedirect = null;
    return value;
  }
}

const config = SpotifyConfig(
  clientId: '0123456789abcdef0123456789abcdef',
  redirectUri: 'retrofy://spotify-callback',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTokenStore store;
  late FakeRedirects redirects;
  late List<Uri> launched;
  late List<http.Request> tokenRequests;
  late http.Response Function(http.Request) tokenResponse;
  late DateTime now;

  ProviderContainer container({SpotifyConfig spotifyConfig = config}) {
    final container = ProviderContainer(
      overrides: [
        spotifyConfigProvider.overrideWithValue(spotifyConfig),
        spotifyTokenStoreProvider.overrideWithValue(store),
        spotifyRedirectChannelProvider.overrideWithValue(redirects),
        spotifyClockProvider.overrideWithValue(() => now),
        spotifyBrowserLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return true;
        }),
        spotifyAuthClientProvider.overrideWith(
          (ref) => SpotifyAuthClient(
            spotifyConfig,
            now: () => now,
            client: MockClient((request) async {
              tokenRequests.add(request);
              return tokenResponse(request);
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  http.Response tokens(String access, {int expiresIn = 3600}) => http.Response(
    jsonEncode({
      'access_token': access,
      'refresh_token': 'refresh-$access',
      'expires_in': expiresIn,
    }),
    200,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    store = MemoryTokenStore();
    redirects = FakeRedirects();
    launched = [];
    tokenRequests = [];
    tokenResponse = (_) => tokens('access');
    now = DateTime(2026, 1, 1, 12);
  });

  group('spotify_sign_in', () {
    test('without a client id Spotify reports not configured', () async {
      final c = container(
        spotifyConfig: const SpotifyConfig(clientId: '', redirectUri: 'x'),
      );
      final state = await c.read(spotifyAuthControllerProvider.future);
      expect(state.status, SpotifyAuthStatus.notConfigured);
      await c.read(spotifyAuthControllerProvider.notifier).signIn();
      expect(launched, isEmpty);
    });

    test('opens the browser and completes on the matching redirect', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      await c.read(spotifyAuthControllerProvider.notifier).signIn();
      expect(
        c.read(spotifyAuthControllerProvider).value!.status,
        SpotifyAuthStatus.signingIn,
      );
      final authorize = launched.single;
      final state = authorize.queryParameters['state']!;
      expect(store.pending!.state, state);

      redirects.controller.add(
        Uri.parse('retrofy://spotify-callback?code=abc&state=$state'),
      );
      await settle();
      await settle();

      expect(
        c.read(spotifyAuthControllerProvider).value!.status,
        SpotifyAuthStatus.signedIn,
      );
      expect(store.tokens!.accessToken, 'access');
      expect(store.pending, isNull);
      expect(tokenRequests.single.bodyFields['code_verifier'], isNot(isEmpty));
    });

    test('completes a redirect that cold-started the app', () async {
      final session = SpotifyPkceSession.generate(now: now);
      store.pending = session;
      redirects.pendingRedirect = Uri.parse(
        'retrofy://spotify-callback?code=abc&state=${session.state}',
      );
      final c = container();
      final state = await c.read(spotifyAuthControllerProvider.future);
      expect(state.status, SpotifyAuthStatus.signedIn);
      expect(
        tokenRequests.single.bodyFields['code_verifier'],
        session.verifier,
      );
    });

    test('a leftover redirect at startup keeps the saved session', () async {
      // Seen on device: after a crash the restarted app received a redirect
      // from the earlier attempt and replaced a valid session with an error.
      store.tokens = SpotifyTokens(
        accessToken: 'saved',
        refreshToken: 'refresh-saved',
        expiresAt: DateTime(2026, 1, 1, 13),
        scope: '',
      );
      redirects.pendingRedirect = Uri.parse(
        'retrofy://spotify-callback/?code=old&state=old',
      );
      final c = container();
      final state = await c.read(spotifyAuthControllerProvider.future);
      expect(state.status, SpotifyAuthStatus.signedIn);
      expect(state.error, isNull);
      expect(tokenRequests, isEmpty);
      expect(store.tokens!.accessToken, 'saved');
    });

    test(
      'a stray redirect while signed out is not shown as a failure',
      () async {
        redirects.pendingRedirect = Uri.parse(
          'retrofy://spotify-callback/?code=old&state=old',
        );
        final c = container();
        final state = await c.read(spotifyAuthControllerProvider.future);
        expect(state.status, SpotifyAuthStatus.signedOut);
        expect(state.error, isNull);
      },
    );

    test('rejects a redirect with a forged state', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      await c.read(spotifyAuthControllerProvider.notifier).signIn();
      redirects.controller.add(
        Uri.parse('retrofy://spotify-callback?code=abc&state=forged'),
      );
      await settle();
      await settle();
      final state = c.read(spotifyAuthControllerProvider).value!;
      expect(state.status, SpotifyAuthStatus.signedOut);
      expect(state.error, 'state_mismatch');
      expect(tokenRequests, isEmpty);
      expect(store.tokens, isNull);
    });

    test('ignores a duplicate redirect after signing in', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      await c.read(spotifyAuthControllerProvider.notifier).signIn();
      final redirect = Uri.parse(
        'retrofy://spotify-callback?code=abc&state='
        '${launched.single.queryParameters['state']}',
      );
      redirects.controller.add(redirect);
      await settle();
      await settle();
      redirects.controller.add(redirect);
      await settle();
      await settle();
      expect(
        c.read(spotifyAuthControllerProvider).value!.status,
        SpotifyAuthStatus.signedIn,
      );
      expect(tokenRequests, hasLength(1));
    });
  });

  group('spotify_tokens', () {
    setUp(() {
      store.tokens = SpotifyTokens(
        accessToken: 'saved',
        refreshToken: 'refresh-saved',
        expiresAt: DateTime(2026, 1, 1, 13),
        scope: '',
      );
    });

    test('uses the stored token until it nears expiry', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      final auth = c.read(spotifyAuthControllerProvider.notifier);
      expect(await auth.accessToken(), 'saved');
      expect(tokenRequests, isEmpty);

      now = DateTime(2026, 1, 1, 12, 59, 30);
      tokenResponse = (_) => tokens('renewed');
      expect(await auth.accessToken(), 'renewed');
      expect(store.tokens!.accessToken, 'renewed');
    });

    test('concurrent callers share one refresh', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      final auth = c.read(spotifyAuthControllerProvider.notifier);
      tokenResponse = (_) => tokens('renewed');
      final results = await Future.wait([
        auth.accessToken(forceRefresh: true),
        auth.accessToken(forceRefresh: true),
        auth.accessToken(forceRefresh: true),
      ]);
      expect(results, ['renewed', 'renewed', 'renewed']);
      expect(tokenRequests, hasLength(1));
    });

    test('a revoked refresh token signs out with an explanation', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      tokenResponse = (_) => http.Response('{"error":"invalid_grant"}', 400);
      await expectLater(
        c
            .read(spotifyAuthControllerProvider.notifier)
            .accessToken(forceRefresh: true),
        throwsA(isA<SpotifyException>()),
      );
      final state = c.read(spotifyAuthControllerProvider).value!;
      expect(state.status, SpotifyAuthStatus.signedOut);
      expect(state.error, 'session_expired');
      expect(store.tokens, isNull);
    });

    test('a network failure during refresh keeps the session', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      tokenResponse = (_) => throw Exception('offline');
      await expectLater(
        c
            .read(spotifyAuthControllerProvider.notifier)
            .accessToken(forceRefresh: true),
        throwsA(
          isA<SpotifyException>().having((e) => e.code, 'code', 'connection'),
        ),
      );
      expect(
        c.read(spotifyAuthControllerProvider).value!.status,
        SpotifyAuthStatus.signedIn,
      );
      expect(store.tokens, isNotNull);
    });

    test('sign out deletes every stored token', () async {
      final c = container();
      await c.read(spotifyAuthControllerProvider.future);
      final auth = c.read(spotifyAuthControllerProvider.notifier);
      await auth.signOut();
      expect(store.tokens, isNull);
      expect(
        c.read(spotifyAuthControllerProvider).value!.status,
        SpotifyAuthStatus.signedOut,
      );
      await expectLater(auth.accessToken(), throwsA(isA<SpotifyException>()));
    });
  });
}
