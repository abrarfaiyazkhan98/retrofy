import 'dart:convert';

import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens and the in-flight PKCE verifier live only in secure storage, which
/// on Android is encrypted with keys held by the Android Keystore.
abstract class SpotifyTokenStore {
  Future<SpotifyTokens?> readTokens();
  Future<void> writeTokens(SpotifyTokens tokens);
  Future<SpotifyPkceSession?> readPending();
  Future<void> writePending(SpotifyPkceSession session);
  Future<void> clearPending();
  Future<void> clear();
}

class SecureSpotifyTokenStore implements SpotifyTokenStore {
  final FlutterSecureStorage storage;
  static const _tokensKey = 'spotify:tokens';
  static const _pendingKey = 'spotify:pending-pkce';

  const SecureSpotifyTokenStore({this.storage = const FlutterSecureStorage()});

  Future<Object?> _read(String key) async {
    final value = await storage.read(key: key);
    if (value == null) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SpotifyTokens?> readTokens() async =>
      SpotifyTokens.fromJson(await _read(_tokensKey));

  @override
  Future<void> writeTokens(SpotifyTokens tokens) =>
      storage.write(key: _tokensKey, value: jsonEncode(tokens.toJson()));

  @override
  Future<SpotifyPkceSession?> readPending() async =>
      SpotifyPkceSession.fromJson(await _read(_pendingKey));

  @override
  Future<void> writePending(SpotifyPkceSession session) =>
      storage.write(key: _pendingKey, value: jsonEncode(session.toJson()));

  @override
  Future<void> clearPending() => storage.delete(key: _pendingKey);

  @override
  Future<void> clear() async {
    await storage.delete(key: _tokensKey);
    await storage.delete(key: _pendingKey);
  }
}
