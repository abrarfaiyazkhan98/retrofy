import 'dart:async';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_config.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/core/spotify/spotify_token_store.dart';
import 'package:classipod/features/device/models/device_action.dart';
import 'package:classipod/features/device/services/device_buttons_service_provider.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/spotify/models/spotify_track_source.dart';
import 'package:classipod/features/spotify/screens/spotify_menu_screen.dart';
import 'package:classipod/features/spotify/screens/spotify_tracks_screen.dart';
import 'package:classipod/l10n/generated/app_localizations.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Click wheel without vibration or click sounds.
class SilentWheel extends DeviceButtonsServiceNotifier {
  @override
  Future<void> setDeviceAction(DeviceAction action) async {
    state = null;
    state = action;
  }
}

class FakeAuth extends SpotifyAuthController {
  final SpotifyAuthState initial;
  int signIns = 0;
  int signOuts = 0;
  FakeAuth(this.initial);

  @override
  Future<SpotifyAuthState> build() async => initial;

  @override
  Future<void> signIn() async => signIns++;

  @override
  Future<void> signOut() async {
    signOuts++;
    state = const AsyncData(SpotifyAuthState(SpotifyAuthStatus.signedOut));
  }
}

class RecordingService extends AudioPlayerServiceNotifier {
  final requests = <({int? index, String? contextUri, bool? shuffle})>[];
  SpotifyException? failure;

  /// Holds playSpotify open, like a first connection awaiting approval.
  Completer<void>? hold;

  @override
  Future<void> build() async {}

  @override
  Future<void> playSpotify({
    required List<MusicMetadata> tracks,
    int? index,
    String? contextUri,
    bool? shuffle,
    NowPlayingType nowPlayingType = NowPlayingType.songs,
  }) async {
    requests.add((index: index, contextUri: contextUri, shuffle: shuffle));
    await hold?.future;
    if (failure != null) throw failure!;
  }
}

MusicMetadata track(String id, int position) => MusicMetadata(
  songId: 'spotify:track:$id',
  trackName: 'Song $id',
  trackArtistNames: const ['Band'],
  originalSongIndex: position,
  isOnDevice: false,
);

/// Unmounts the screens so marquee titles stop their scroll timers.
void spotifyTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

void main() {
  late List<Object?> opened;
  late FakeAuth auth;
  late RecordingService service;
  late ProviderContainer container;

  Future<void> pumpRoute(
    WidgetTester tester,
    String location, {
    Object? extra,
    SpotifyAuthState authState = const SpotifyAuthState(
      SpotifyAuthStatus.signedIn,
      profile: SpotifyProfile(id: 'me', displayName: 'Abrar'),
    ),
  }) async {
    opened = [];
    auth = FakeAuth(authState);
    service = RecordingService();
    container = ProviderContainer(
      overrides: [
        deviceButtonsServiceProvider.overrideWith(SilentWheel.new),
        spotifyAuthControllerProvider.overrideWith(() => auth),
        audioPlayerServiceProvider.overrideWith(() => service),
      ],
    );
    addTearDown(container.dispose);
    GoRoute capture(Routes route) => GoRoute(
      path: route.name,
      name: route.name,
      builder: (_, state) {
        opened.add(state.extra ?? route.name);
        return const SizedBox();
      },
    );
    final router = GoRouter(
      initialLocation: location,
      initialExtra: extra,
      routes: [
        GoRoute(
          path: '/spotify',
          name: Routes.spotify.name,
          builder: (_, _) => const SpotifyMenuScreen(),
          routes: [
            capture(Routes.spotifyBrowse),
            capture(Routes.spotifySearch),
            capture(Routes.nowPlaying),
            GoRoute(
              path: Routes.spotifyTracks.name,
              name: Routes.spotifyTracks.name,
              builder: (_, state) => state.extra is SpotifyTrackSource
                  ? SpotifyTracksScreen(
                      source: state.extra! as SpotifyTrackSource,
                    )
                  : const SizedBox(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 480));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> wheel(WidgetTester tester, DeviceAction action) async {
    await container
        .read(deviceButtonsServiceProvider.notifier)
        .setDeviceAction(action);
    await tester.pumpAndSettle();
  }

  group('spotify_menu', () {
    spotifyTest('signed out offers sign in on the center button', (
      tester,
    ) async {
      await pumpRoute(
        tester,
        '/spotify',
        authState: const SpotifyAuthState(
          SpotifyAuthStatus.signedOut,
          error: 'session_expired',
        ),
      );
      expect(find.text('Sign In to Spotify'), findsOneWidget);
      expect(find.text('Sign in to Spotify again'), findsOneWidget);
      await wheel(tester, DeviceAction.select);
      expect(auth.signIns, 1);
    });

    spotifyTest('a build without a client id says so', (tester) async {
      await pumpRoute(
        tester,
        '/spotify',
        authState: const SpotifyAuthState(SpotifyAuthStatus.notConfigured),
      );
      expect(find.text('Spotify Not Configured'), findsOneWidget);
      await wheel(tester, DeviceAction.select);
      expect(auth.signIns, 0);
    });

    spotifyTest('the click wheel walks the library menu', (tester) async {
      await pumpRoute(tester, '/spotify');
      for (final title in [
        'Playlists',
        'Albums',
        'Artists',
        'Liked Songs',
        'Recently Played',
        'Search',
        'Signed in as Abrar',
        'Sign Out',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      await wheel(tester, DeviceAction.rotateForward);
      await wheel(tester, DeviceAction.rotateForward);
      await wheel(tester, DeviceAction.select);
      final source = opened.single as SpotifyBrowseSource;
      expect(source.isArtists, isTrue);
    });

    spotifyTest('liked songs play through the user collection', (tester) async {
      await pumpRoute(tester, '/spotify');
      await tester.tap(find.text('Liked Songs'));
      await tester.pumpAndSettle();
      // The tracks screen replaced the capture route; inspect its source.
      final screen = tester.widget<SpotifyTracksScreen>(
        find.byType(SpotifyTracksScreen),
      );
      expect(screen.source.contextUri, 'spotify:user:me:collection');
    });

    spotifyTest('sign out returns to the sign in row', (tester) async {
      await pumpRoute(tester, '/spotify');
      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.text('Sign In to Spotify'), findsOneWidget);
    });
  });

  group('spotify_tracks', () {
    final tracksProvider = Provider<AsyncValue<List<MusicMetadata>>>(
      (_) => AsyncData([track('a', 0), track('b', 4)]),
    );
    final failingProvider = Provider<AsyncValue<List<MusicMetadata>>>(
      (_) => const AsyncError(SpotifyException('forbidden'), StackTrace.empty),
    );

    spotifyTest('selecting a track plays it at its context position', (
      tester,
    ) async {
      await pumpRoute(
        tester,
        '/spotify/spotifyTracks',
        extra: SpotifyTrackSource(
          title: 'Mix',
          tracks: tracksProvider,
          contextUri: 'spotify:playlist:p',
        ),
      );
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle Play'), findsOneWidget);
      await wheel(tester, DeviceAction.rotateForward);
      await wheel(tester, DeviceAction.rotateForward);
      await wheel(tester, DeviceAction.rotateForward);
      await wheel(tester, DeviceAction.select);
      expect(service.requests.single, (
        index: 1,
        contextUri: 'spotify:playlist:p',
        shuffle: null,
      ));
      expect(opened, [Routes.nowPlaying.name]);
    });

    spotifyTest('repeated taps while connecting send one request', (
      tester,
    ) async {
      await pumpRoute(
        tester,
        '/spotify/spotifyTracks',
        extra: SpotifyTrackSource(
          title: 'Mix',
          tracks: tracksProvider,
          contextUri: 'spotify:playlist:p',
        ),
      );
      service.hold = Completer<void>();
      await tester.tap(find.text('Song b'));
      await tester.pump();
      expect(find.text('Connecting to Spotify…'), findsOneWidget);
      await tester.tap(find.text('Song b'));
      await tester.tap(find.text('Song a'));
      await wheel(tester, DeviceAction.select);
      expect(service.requests, hasLength(1));

      service.hold!.complete();
      await tester.pumpAndSettle();
      expect(service.requests.single.index, 1);
      expect(find.text('Connecting to Spotify…'), findsNothing);
      expect(opened, [Routes.nowPlaying.name]);
    });

    spotifyTest('Shuffle Play plays the whole context shuffled', (
      tester,
    ) async {
      await pumpRoute(
        tester,
        '/spotify/spotifyTracks',
        extra: SpotifyTrackSource(
          title: 'Mix',
          tracks: tracksProvider,
          contextUri: 'spotify:playlist:p',
        ),
      );
      await tester.tap(find.text('Shuffle Play'));
      await tester.pumpAndSettle();
      expect(service.requests.single, (
        index: null,
        contextUri: 'spotify:playlist:p',
        shuffle: true,
      ));
    });

    spotifyTest('playback errors stay on the list with an explanation', (
      tester,
    ) async {
      await pumpRoute(
        tester,
        '/spotify/spotifyTracks',
        extra: SpotifyTrackSource(title: 'Recent', tracks: tracksProvider),
      );
      service.failure = const SpotifyException('premium_required');
      await tester.tap(find.text('Song b'));
      await tester.pumpAndSettle();
      expect(find.text('Spotify Premium required'), findsOneWidget);
      expect(opened, isEmpty);
    });

    spotifyTest('unlistable playlists still offer Play rows', (tester) async {
      await pumpRoute(
        tester,
        '/spotify/spotifyTracks',
        extra: SpotifyTrackSource(
          title: 'Followed',
          tracks: failingProvider,
          contextUri: 'spotify:playlist:x',
        ),
      );
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Not available from Spotify'), findsOneWidget);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(service.requests.single.shuffle, isFalse);
    });

    spotifyTest('lists without context show load errors full screen', (
      tester,
    ) async {
      await pumpRoute(
        tester,
        '/spotify/spotifyTracks',
        extra: SpotifyTrackSource(title: 'Recent', tracks: failingProvider),
      );
      expect(find.text('Not available from Spotify'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
    });
  });

  spotifyTest('cancelling the browser login returns to signed out', (
    tester,
  ) async {
    final completer = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        spotifyRedirectChannelProvider.overrideWithValue(_NoRedirects()),
        spotifyTokenStoreProvider.overrideWithValue(_NullStore()),
        spotifyConfigProvider.overrideWithValue(
          const SpotifyConfig(
            clientId: '0123456789abcdef0123456789abcdef',
            redirectUri: 'retrofy://spotify-callback',
          ),
        ),
        spotifyBrowserLauncherProvider.overrideWithValue((_) async {
          completer.complete();
          return true;
        }),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(spotifyAuthControllerProvider, (_, _) {});
    addTearDown(sub.close);
    await tester.runAsync(
      () => container.read(spotifyAuthControllerProvider.future),
    );
    await tester.runAsync(
      () => container.read(spotifyAuthControllerProvider.notifier).signIn(),
    );
    expect(completer.isCompleted, isTrue);
    expect(
      container.read(spotifyAuthControllerProvider).value!.status,
      SpotifyAuthStatus.signingIn,
    );
    // The browser covers the app, then the user comes back without signing in.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(seconds: 4));
    expect(
      container.read(spotifyAuthControllerProvider).value!.status,
      SpotifyAuthStatus.signedOut,
    );
  });
}

class _NoRedirects extends SpotifyRedirectChannel {
  @override
  Stream<Uri> get redirects => const Stream.empty();

  @override
  Future<Uri?> takePending() async => null;
}

class _NullStore implements SpotifyTokenStore {
  @override
  Future<SpotifyTokens?> readTokens() async => null;
  @override
  Future<void> writeTokens(SpotifyTokens tokens) async {}
  @override
  Future<SpotifyPkceSession?> readPending() async => null;
  @override
  Future<void> writePending(SpotifyPkceSession session) async {}
  @override
  Future<void> clearPending() async {}
  @override
  Future<void> clear() async {}
}
