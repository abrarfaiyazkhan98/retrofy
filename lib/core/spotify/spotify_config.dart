/// Build-time Spotify settings. Only the public Client ID is configured here;
/// PKCE means no Client Secret ever ships with the app.
class SpotifyConfig {
  final String clientId;
  final String redirectUri;

  const SpotifyConfig({required this.clientId, required this.redirectUri});

  /// Supplied with `--dart-define-from-file=spotify.config.json`, which is
  /// ignored by Git so the dashboard values never land in history.
  const SpotifyConfig.fromEnvironment()
    : clientId = const String.fromEnvironment('SPOTIFY_CLIENT_ID'),
      redirectUri = const String.fromEnvironment(
        'SPOTIFY_REDIRECT_URI',
        defaultValue: defaultRedirectUri,
      );

  /// Must match the intent filter in AndroidManifest.xml and the redirect URI
  /// registered on the Spotify Developer Dashboard.
  static const defaultRedirectUri = 'retrofy://spotify-callback';

  /// Used only by Spotify's Android auth library when asking for playback
  /// control. It needs its own address (declared on the library's receiver in
  /// AndroidManifest.xml) and must also be registered on the dashboard.
  static const appRemoteRedirectUri = 'retrofy://spotify-app-remote';

  /// Only the scopes the implemented screens need.
  static const scopes = [
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-library-read',
    'user-follow-read',
    'user-read-recently-played',
  ];

  bool get isConfigured => RegExp(r'^[0-9a-zA-Z]{32}$').hasMatch(clientId);
}
