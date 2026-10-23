import 'dart:io';

import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts declared for the `retrofy` scheme by the activity named [name].
Set<String> hostsFor(String manifest, String name) {
  final start = manifest.indexOf('android:name="$name"');
  expect(start, isNot(-1), reason: '$name must be declared');
  final end = manifest.indexOf('</activity>', start);
  return RegExp(r'android:scheme="retrofy"\s+android:host="([^"]+)"')
      .allMatches(manifest.substring(start, end))
      .map((match) => match.group(1)!)
      .toSet();
}

void main() {
  group('spotify_manifest', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    test('auth library receiver declares its redirect', () {
      // Spotify auth 5.x crashes LoginActivity (and with it the app) when its
      // RedirectUriReceiverActivity has no filter for the redirect it is given.
      expect(
        hostsFor(
          manifest,
          'com.spotify.sdk.android.auth.browser.RedirectUriReceiverActivity',
        ),
        {Uri.parse(SpotifyConfig.appRemoteRedirectUri).host},
      );
    });

    test("sign-in redirect goes only to Retrofy's receiver", () {
      expect(hostsFor(manifest, '.SpotifyAuthRedirectActivity'), {
        Uri.parse(SpotifyConfig.defaultRedirectUri).host,
      });
      expect(
        SpotifyConfig.appRemoteRedirectUri,
        isNot(SpotifyConfig.defaultRedirectUri),
        reason: 'two receivers for one address make Android ask which to use',
      );
    });
  });
}
