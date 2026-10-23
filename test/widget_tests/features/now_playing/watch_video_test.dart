import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/models/playback_shuffle_mode.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/screen/now_playing_more_options_screen.dart';
import 'package:classipod/features/now_playing/video/music_video_link.dart';
import 'package:classipod/l10n/generated/app_localizations.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

final spotifySong = MusicMetadata(
  songId: 'spotify:track:abc',
  trackName: 'Champagne In The Morning',
  trackArtistNames: const ['Redferrin'],
  isOnDevice: false,
);
final localSong = MusicMetadata(
  songId: 'local',
  trackName: 'Faded',
  trackArtistNames: const ['Alan Walker'],
  filePath: '/music/faded.mp3',
);

class FixedNowPlaying extends NowPlayingDetailsNotifier {
  final MusicMetadata song;
  FixedNowPlaying(this.song);

  @override
  NowPlayingModel build() => NowPlayingModel(
    currentIndex: 0,
    isPlaying: true,
    nowPlayingType: NowPlayingType.songs,
    currentMetadata: song,
    metadataList: [song],
    shuffleMode: PlaybackShuffleMode.off,
    loopMode: LoopMode.off,
  );
}

class RecordingService extends AudioPlayerServiceNotifier {
  final events = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> pause() async => events.add('pause');
}

void main() {
  group('watch_video', () {
    test('searches YouTube for the official video', () {
      final uri = musicVideoSearchUri(spotifySong)!;
      expect(uri.host, 'www.youtube.com');
      expect(uri.path, '/results');
      expect(
        uri.queryParameters['search_query'],
        'Redferrin Champagne In The Morning official video',
      );
      expect(musicVideoSearchUri(MusicMetadata()), isNull);
      expect(musicVideoSearchUri(null), isNull);
    });

    Future<RecordingService> pumpOptions(
      WidgetTester tester,
      MusicMetadata song,
      List<Uri> launched,
    ) async {
      final service = RecordingService();
      // Options open over Now Playing in the app, so closing pops back.
      final router = GoRouter(
        initialLocation: '/options',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SizedBox(),
            routes: [
              GoRoute(
                path: 'options',
                name: Routes.nowPlayingMoreOptions.name,
                builder: (_, _) => const NowPlayingMoreOptionsScreen(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nowPlayingDetailsProvider.overrideWith(() => FixedNowPlaying(song)),
            audioPlayerServiceProvider.overrideWith(() => service),
            musicVideoLauncherProvider.overrideWithValue((uri) async {
              launched.add(uri);
              service.events.add('launch');
              return true;
            }),
          ],
          child: CupertinoApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('Spotify tracks offer only applicable options', (tester) async {
      final launched = <Uri>[];
      final service = await pumpOptions(tester, spotifySong, launched);
      expect(find.text('Watch Video'), findsOneWidget);
      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(find.text('Add to On-The-Go'), findsNothing);
      expect(find.text('Edit Song'), findsNothing);

      await tester.tap(find.text('Watch Video'));
      await tester.pumpAndSettle();
      expect(service.events, ['pause', 'launch']);
      expect(launched.single, musicVideoSearchUri(spotifySong));
    });

    testWidgets('local tracks keep their library options', (tester) async {
      await pumpOptions(tester, localSong, []);
      expect(find.text('Watch Video'), findsOneWidget);
      expect(find.text('Edit Song'), findsOneWidget);
    });
  });
}
