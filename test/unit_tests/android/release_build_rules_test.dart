import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release builds shrink and rename code with R8, which the Dart test suite
/// never runs. These guard the two release-only failures found on device.
void main() {
  group('release_build_rules', () {
    test('Spotify locator constructors survive R8', () {
      // App Remote reflects on these classes; without their constructors
      // isSpotifyInstalled() is false and playback says "Install Spotify".
      final rules = File('android/app/proguard-rules.pro').readAsStringSync();
      for (final locator in ['ReleaseSpotifyLocator', 'DebugSpotifyLocator']) {
        expect(
          RegExp(
            r'-keep class com\.spotify\.android\.appremote\.internal\.' +
                locator +
                r' \{[^}]*public <init>\(\);',
          ).hasMatch(rules),
          isTrue,
          reason: '$locator must keep its constructor',
        );
      }
      expect(
        File('android/app/build.gradle.kts').readAsStringSync(),
        contains('"proguard-rules.pro"'),
      );
    });

    test('Spotify errors are matched by type, not class name', () {
      // R8 renames the SDK's exception classes in release builds.
      final bridge = File(
        'android/app/src/main/kotlin/com/abrarfaiyazkhan/retrofy/'
        'SpotifyRemoteBridge.kt',
      ).readAsStringSync();
      expect(bridge, isNot(contains('simpleName')));
      expect(bridge, contains('is UserNotAuthorizedException ->'));
    });
  });
}
