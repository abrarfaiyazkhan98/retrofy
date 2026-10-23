import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Error codes are stable strings so the UI can localize them and tests can
/// assert on them without depending on message text.
class SpotifyException implements Exception {
  final String code;
  const SpotifyException(this.code);

  @override
  String toString() => 'Spotify: $code';
}

/// One authorization attempt: the verifier stays on the device and only its
/// S256 challenge is sent to Spotify, and [state] binds the redirect to it.
class SpotifyPkceSession {
  static const _unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  final String verifier;
  final String state;
  final DateTime createdAt;

  const SpotifyPkceSession({
    required this.verifier,
    required this.state,
    required this.createdAt,
  });

  factory SpotifyPkceSession.generate({Random? random, DateTime? now}) {
    final source = random ?? Random.secure();
    String token(int length) => List.generate(
      length,
      (_) => _unreserved[source.nextInt(_unreserved.length)],
    ).join();
    return SpotifyPkceSession(
      verifier: token(64),
      state: token(32),
      createdAt: now ?? DateTime.now(),
    );
  }

  String get challenge => challengeFor(verifier);

  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  /// Abandoned logins should not be completable long after the fact.
  bool expired(DateTime now) =>
      now.difference(createdAt) > const Duration(minutes: 10);

  Uri authorizeUri(SpotifyConfig config) =>
      Uri.https('accounts.spotify.com', '/authorize', {
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': config.redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
        'scope': SpotifyConfig.scopes.join(' '),
      });

  /// Returns the authorization code, or throws when the redirect does not
  /// belong to this attempt or Spotify reported an error.
  String codeFrom(Uri redirect, SpotifyConfig config) {
    final expected = Uri.parse(config.redirectUri);
    // Spotify answers retrofy://spotify-callback with a root path
    // (retrofy://spotify-callback/?code=...), so '' and '/' are equivalent.
    String path(Uri uri) => uri.path == '/' ? '' : uri.path;
    if (redirect.scheme != expected.scheme ||
        redirect.host != expected.host ||
        path(redirect) != path(expected)) {
      throw const SpotifyException('redirect_mismatch');
    }
    final parameters = redirect.queryParameters;
    if (parameters['state'] != state) {
      throw const SpotifyException('state_mismatch');
    }
    final error = parameters['error'];
    if (error != null) {
      throw SpotifyException(
        error == 'access_denied' ? 'access_denied' : 'authorization_failed',
      );
    }
    final code = parameters['code'];
    if (code == null || code.isEmpty) {
      throw const SpotifyException('authorization_failed');
    }
    return code;
  }

  Map<String, dynamic> toJson() => {
    'verifier': verifier,
    'state': state,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static SpotifyPkceSession? fromJson(Object? value) {
    if (value is! Map) return null;
    final verifier = value['verifier'];
    final state = value['state'];
    final createdAt = value['createdAt'];
    if (verifier is! String || state is! String || createdAt is! int) {
      return null;
    }
    return SpotifyPkceSession(
      verifier: verifier,
      state: state,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
    );
  }
}

class SpotifyTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String scope;

  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scope,
  });

  /// Refresh a minute early so requests never race the expiry.
  bool expired(DateTime now) =>
      !now.isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'scope': scope,
  };

  static SpotifyTokens? fromJson(Object? value) {
    if (value is! Map) return null;
    final access = value['accessToken'];
    final refresh = value['refreshToken'];
    final expiresAt = value['expiresAt'];
    if (access is! String || refresh is! String || expiresAt is! int) {
      return null;
    }
    return SpotifyTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      scope: value['scope'] as String? ?? '',
    );
  }
}

/// Talks to the accounts service. Public client: the Client ID identifies the
/// app and the PKCE verifier proves possession, so no secret is sent.
class SpotifyAuthClient {
  final SpotifyConfig config;
  final http.Client _http;
  final DateTime Function() _now;

  SpotifyAuthClient(
    this.config, {
    http.Client? client,
    DateTime Function()? now,
  }) : _http = client ?? http.Client(),
       _now = now ?? DateTime.now;

  static final _tokenUri = Uri.https('accounts.spotify.com', '/api/token');

  Future<SpotifyTokens> exchangeCode(String code, String verifier) => _token({
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': config.redirectUri,
    'code_verifier': verifier,
  });

  /// Spotify may rotate the refresh token; keep the old one when it doesn't.
  Future<SpotifyTokens> refresh(SpotifyTokens tokens) => _token({
    'grant_type': 'refresh_token',
    'refresh_token': tokens.refreshToken,
  }, previousRefreshToken: tokens.refreshToken);

  Future<SpotifyTokens> _token(
    Map<String, String> body, {
    String? previousRefreshToken,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _tokenUri,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {...body, 'client_id': config.clientId},
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const SpotifyException('timeout');
    } catch (_) {
      throw const SpotifyException('connection');
    }
    Map<String, dynamic>? data;
    try {
      data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode != 200) {
      // Spotify's error fields describe the cause and never contain the
      // code, verifier or tokens, so they are safe to log.
      debugPrint(
        'Spotify token request failed: HTTP ${response.statusCode} '
        '${data?['error']} ${data?['error_description']}',
      );
    }
    if (response.statusCode == 400 || response.statusCode == 401) {
      // invalid_grant: the refresh token was revoked or the code was reused.
      throw SpotifyException(
        data?['error'] == 'invalid_grant' ? 'session_expired' : 'auth_failed',
      );
    }
    if (response.statusCode == 429) {
      throw const SpotifyException('rate_limited');
    }
    if (response.statusCode != 200 || data == null) {
      throw const SpotifyException('server');
    }
    final access = data['access_token'];
    final expiresIn = data['expires_in'];
    final refresh = data['refresh_token'] ?? previousRefreshToken;
    if (access is! String || expiresIn is! int || refresh is! String) {
      throw const SpotifyException('response');
    }
    return SpotifyTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: _now().add(Duration(seconds: expiresIn)),
      scope: data['scope'] as String? ?? '',
    );
  }

  void close() => _http.close();
}
