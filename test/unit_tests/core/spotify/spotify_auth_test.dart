import 'dart:convert';
import 'dart:math';

import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const config = SpotifyConfig(
  clientId: '0123456789abcdef0123456789abcdef',
  redirectUri: 'retrofy://spotify-callback',
);

SpotifyPkceSession session({DateTime? at}) => SpotifyPkceSession(
  verifier: 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
  state: 'state-123',
  createdAt: at ?? DateTime(2026),
);

void main() {
  group('pkce', () {
    test('matches the RFC 7636 S256 test vector', () {
      expect(
        SpotifyPkceSession.challengeFor(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('generates unreserved verifiers and unique states', () {
      final first = SpotifyPkceSession.generate(random: Random(1));
      final second = SpotifyPkceSession.generate(random: Random(2));
      expect(first.verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]{64}$')));
      expect(first.state, hasLength(32));
      expect(first.state, isNot(second.state));
      expect(first.challenge, isNot(contains('=')));
    });

    test('authorize URL sends only the challenge and requested scopes', () {
      final uri = session().authorizeUri(config);
      expect(uri.host, 'accounts.spotify.com');
      expect(uri.path, '/authorize');
      expect(uri.queryParameters, {
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': 'retrofy://spotify-callback',
        'code_challenge_method': 'S256',
        'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
        'state': 'state-123',
        'scope': SpotifyConfig.scopes.join(' '),
      });
      expect(uri.toString(), isNot(contains('dBjftJeZ4CVP')));
    });

    test('accepts a redirect carrying the matching state', () {
      final code = session().codeFrom(
        Uri.parse('retrofy://spotify-callback?code=abc&state=state-123'),
        config,
      );
      expect(code, 'abc');
    });

    test('accepts the root path Spotify adds to the redirect', () {
      // Exactly what Spotify sent back on a real Android device.
      final code = session().codeFrom(
        Uri.parse('retrofy://spotify-callback/?code=abc&state=state-123'),
        config,
      );
      expect(code, 'abc');
    });

    test('rejects forged, failed and foreign redirects', () {
      void expectCode(String redirect, String code) => expect(
        () => session().codeFrom(Uri.parse(redirect), config),
        throwsA(isA<SpotifyException>().having((e) => e.code, 'code', code)),
      );
      expectCode(
        'retrofy://spotify-callback?code=abc&state=other',
        'state_mismatch',
      );
      expectCode('retrofy://spotify-callback?code=abc', 'state_mismatch');
      expectCode(
        'retrofy://spotify-callback?error=access_denied&state=state-123',
        'access_denied',
      );
      expectCode(
        'retrofy://spotify-callback?state=state-123',
        'authorization_failed',
      );
      expectCode(
        'retrofy://spotify-callback/other?code=abc&state=state-123',
        'redirect_mismatch',
      );
      expectCode(
        'retrofy://elsewhere/?code=abc&state=state-123',
        'redirect_mismatch',
      );
      expectCode(
        'evil://spotify-callback?code=abc&state=state-123',
        'redirect_mismatch',
      );
    });

    test('expires abandoned attempts after ten minutes', () {
      final started = session(at: DateTime(2026, 1, 1, 12));
      expect(started.expired(DateTime(2026, 1, 1, 12, 9)), isFalse);
      expect(started.expired(DateTime(2026, 1, 1, 12, 11)), isTrue);
    });

    test('round-trips through storage json', () {
      final restored = SpotifyPkceSession.fromJson(
        jsonDecode(jsonEncode(session().toJson())),
      )!;
      expect(restored.verifier, session().verifier);
      expect(restored.state, 'state-123');
      expect(SpotifyPkceSession.fromJson({'state': 1}), isNull);
    });
  });

  group('tokens', () {
    test('refresh one minute before expiry', () {
      final tokens = SpotifyTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime(2026, 1, 1, 13),
        scope: '',
      );
      expect(tokens.expired(DateTime(2026, 1, 1, 12, 58)), isFalse);
      expect(tokens.expired(DateTime(2026, 1, 1, 12, 59, 30)), isTrue);
      expect(SpotifyTokens.fromJson(tokens.toJson())!.refreshToken, 'r');
    });
  });

  group('token exchange', () {
    late List<http.Request> requests;
    late http.Response Function(http.Request) respond;
    final now = DateTime(2026, 1, 1, 12);

    SpotifyAuthClient client() => SpotifyAuthClient(
      config,
      now: () => now,
      client: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );

    setUp(() {
      requests = [];
      respond = (_) => http.Response(
        jsonEncode({
          'access_token': 'access',
          'refresh_token': 'refresh',
          'expires_in': 3600,
          'scope': 'user-library-read',
        }),
        200,
      );
    });

    test('exchanges the code with the verifier and no client secret', () async {
      final tokens = await client().exchangeCode('abc', 'verifier');
      final body = requests.single.bodyFields;
      expect(
        requests.single.url.toString(),
        'https://accounts.spotify.com/api/token',
      );
      expect(body, {
        'grant_type': 'authorization_code',
        'code': 'abc',
        'redirect_uri': 'retrofy://spotify-callback',
        'code_verifier': 'verifier',
        'client_id': config.clientId,
      });
      expect(body.keys, isNot(contains('client_secret')));
      expect(requests.single.headers.keys, isNot(contains('Authorization')));
      expect(tokens.accessToken, 'access');
      expect(tokens.expiresAt, now.add(const Duration(hours: 1)));
    });

    test('keeps the refresh token when Spotify does not rotate it', () async {
      respond = (_) => http.Response(
        jsonEncode({'access_token': 'new', 'expires_in': 3600}),
        200,
      );
      final refreshed = await client().refresh(
        SpotifyTokens(
          accessToken: 'old',
          refreshToken: 'keep-me',
          expiresAt: now,
          scope: '',
        ),
      );
      expect(requests.single.bodyFields['grant_type'], 'refresh_token');
      expect(requests.single.bodyFields['refresh_token'], 'keep-me');
      expect(refreshed.accessToken, 'new');
      expect(refreshed.refreshToken, 'keep-me');
    });

    test('maps revoked grants, throttling and outages', () async {
      Future<String> codeFor(http.Response response) async {
        respond = (_) => response;
        try {
          await client().exchangeCode('abc', 'verifier');
        } on SpotifyException catch (error) {
          return error.code;
        }
        return 'none';
      }

      expect(
        await codeFor(http.Response('{"error":"invalid_grant"}', 400)),
        'session_expired',
      );
      expect(
        await codeFor(http.Response('{"error":"invalid_client"}', 400)),
        'auth_failed',
      );
      expect(await codeFor(http.Response('', 429)), 'rate_limited');
      expect(await codeFor(http.Response('', 503)), 'server');
      expect(
        await codeFor(http.Response('{"access_token":1}', 200)),
        'response',
      );
    });

    test('reports network failures as connection errors', () async {
      final failing = SpotifyAuthClient(
        config,
        client: MockClient((_) => throw const SocketLikeException()),
      );
      await expectLater(
        failing.exchangeCode('abc', 'verifier'),
        throwsA(
          isA<SpotifyException>().having((e) => e.code, 'code', 'connection'),
        ),
      );
    });
  });

  test('configuration requires a 32 character client id', () {
    expect(config.isConfigured, isTrue);
    expect(
      const SpotifyConfig(clientId: '', redirectUri: 'x').isConfigured,
      isFalse,
    );
    expect(
      const SpotifyConfig(clientId: 'not-an-id', redirectUri: 'x').isConfigured,
      isFalse,
    );
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
