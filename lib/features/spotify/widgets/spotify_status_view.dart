import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/widgets/empty_state_widget.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

String spotifyErrorText(BuildContext context, Object? error) {
  final l10n = context.localization;
  final code = error is SpotifyException ? error.code : error?.toString();
  return switch (code) {
    'not_installed' => l10n.spotifyErrorNotInstalled,
    'not_logged_in' => l10n.spotifyErrorNotLoggedIn,
    'not_authorized' || 'auth_failed' => l10n.spotifyErrorNotAuthorized,
    'premium_required' => l10n.spotifyErrorPremium,
    'offline' => l10n.spotifyErrorOffline,
    'connection' || 'timeout' => l10n.spotifyErrorConnection,
    'session_expired' || 'signin' => l10n.spotifyErrorSessionExpired,
    'rate_limited' => l10n.spotifyErrorRateLimited,
    'user_not_registered' => l10n.spotifyErrorNotRegistered,
    'state_mismatch' ||
    'redirect_mismatch' ||
    'access_denied' ||
    'authorization_failed' ||
    'browser' ||
    'storage' => l10n.spotifyErrorSignInFailed,
    'forbidden' || 'not_found' => l10n.spotifyErrorUnavailable,
    'not_configured' => l10n.spotifyNotConfigured,
    'wrong_track' => l10n.spotifyErrorWrongTrack,
    _ => l10n.spotifyErrorGeneric,
  };
}

/// Full-screen loading or error state for Spotify lists, in the same style as
/// the app's empty-library screens.
class SpotifyStatusView extends StatelessWidget {
  final Object? error;
  final String? message;

  const SpotifyStatusView.loading({super.key}) : error = null, message = null;

  const SpotifyStatusView.error(this.error, {super.key}) : message = null;

  const SpotifyStatusView.message(this.message, {super.key}) : error = null;

  @override
  Widget build(BuildContext context) {
    final text =
        message ?? (error == null ? null : spotifyErrorText(context, error));
    return CupertinoPageScaffold(
      child: Column(
        children: [
          Expanded(
            child: text == null
                ? const Center(child: CupertinoActivityIndicator())
                : EmptyStateWidget(emptyDescription: text),
          ),
        ],
      ),
    );
  }
}
