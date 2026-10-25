import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/features/mood/engine/mood_engine.dart';
import 'package:classipod/features/mood/models/mood_selection.dart';
import 'package:classipod/features/mood/screens/match_mood_screens.dart';
import 'package:classipod/l10n/generated/app_localizations.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<List<MoodSession>> _mount(
  WidgetTester tester,
  MoodSelection selection,
  MoodSession session,
) async {
  final started = <MoodSession>[];
  final router = GoRouter(
    initialLocation: '/moodPreview',
    routes: [
      GoRoute(
        path: '/moodPreview',
        name: 'moodPreview',
        builder: (_, _) => MoodPreviewScreen(selection: selection),
      ),
      GoRoute(
        path: '/nowPlaying',
        name: 'nowPlaying',
        builder: (_, _) => const SizedBox(key: Key('now-playing')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        moodSessionProvider.overrideWith((_, _) async => session),
        moodSessionStarterProvider.overrideWithValue((s) async {
          started.add(s);
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
  return started;
}

void main() {
  group('match_your_mood_preview', () {
    testWidgets('a playlist match says how it was chosen and starts', (
      tester,
    ) async {
      const selection = MoodChoice(Mood.chill);
      final session = MoodSession(
        selection: selection,
        basis: MatchBasis.playlistName,
        contextUri: 'spotify:playlist:p',
        sourceName: 'Sunday Chill',
        tracks: [
          MusicMetadata(songId: 'spotify:track:a', trackName: 'Slow Song'),
        ],
        spotify: true,
      );
      final started = await _mount(tester, selection, session);
      expect(find.textContaining('Sunday Chill'), findsOneWidget);
      expect(find.textContaining('chosen by its name'), findsOneWidget);
      expect(find.text('Slow Song'), findsOneWidget);
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      expect(started.single, session);
      expect(find.byKey(const Key('now-playing')), findsOneWidget);
    });

    testWidgets('an unmatched tempo is explained, not faked', (tester) async {
      const selection = TempoChoice(120, 140);
      final session = MoodSession(
        selection: selection,
        basis: MatchBasis.noTempoData,
        contextUri: 'spotify:user:u1:collection',
        tracks: [
          MusicMetadata(songId: 'spotify:track:a', trackName: 'Liked Song'),
        ],
        spotify: true,
      );
      await _mount(tester, selection, session);
      expect(find.textContaining('can’t match a tempo'), findsOneWidget);
      expect(find.text('Shuffle Liked Songs Instead'), findsOneWidget);
      expect(find.text('Start Session'), findsNothing);
      expect(
        find.text('Liked Song'),
        findsNothing,
        reason: 'unmatched tracks are not previewed as a tempo match',
      );
    });

    testWidgets('a library without BPM tags cannot start a tempo', (
      tester,
    ) async {
      const selection = TempoChoice(60, 85);
      await _mount(
        tester,
        selection,
        const MoodSession(
          selection: selection,
          basis: MatchBasis.noTempoData,
          spotify: false,
        ),
      );
      expect(find.textContaining('Nothing to play'), findsOneWidget);
      expect(find.text('Shuffle Liked Songs Instead'), findsNothing);
    });
  });
}
