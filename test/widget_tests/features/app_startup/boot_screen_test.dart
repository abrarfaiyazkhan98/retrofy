import 'dart:async';

import 'package:classipod/core/repositories/library/library_progress.dart';
import 'package:classipod/features/app_startup/controllers/app_startup_controller.dart';
import 'package:classipod/features/app_startup/controllers/splash_controller.dart';
import 'package:classipod/features/app_startup/widgets/boot_screen.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Splash stage the test finishes or fails by hand.
class _Splash extends SplashControllerNotifier {
  static Completer<void> done = Completer();

  @override
  Future<void> build() => done.future;
}

class _Library extends LibraryProgressNotifier {
  @override
  LibraryProgress build() => const LibraryProgress();
}

void main() {
  group('boot_progress', () {
    const loading = AsyncLoading<void>();
    const ready = AsyncData<void>(null);

    test('follows the real startup steps', () {
      double at(
        AsyncValue<void> startup,
        AsyncValue<void>? splash, [
        LibraryProgress library = const LibraryProgress(),
      ]) => bootProgress(startup: startup, splash: splash, library: library);

      expect(at(loading, null), 0);
      expect(at(ready, null), 0.15);
      expect(at(ready, loading), 0.2);
      final half = at(
        ready,
        loading,
        const LibraryProgress(
          phase: LibraryPhase.metadata,
          songsTotal: 200,
          songsLoaded: 100,
        ),
      );
      expect(half, closeTo(0.55, 0.001));
      expect(
        at(ready, loading, const LibraryProgress(phase: LibraryPhase.complete)),
        0.92,
      );
      expect(at(ready, ready), 1);
    });

    test('a library with no count yet does not invent progress', () {
      expect(
        bootProgress(
          startup: const AsyncData(null),
          splash: const AsyncLoading(),
          library: const LibraryProgress(phase: LibraryPhase.metadata),
        ),
        0.2,
      );
    });
  });

  group('boot_screen', () {
    late Completer<void> startup;

    // Completers are made inside each test so they complete in the test's
    // fake-async zone.
    Future<void> pump(WidgetTester tester, {bool reduceMotion = false}) {
      startup = Completer();
      _Splash.done = Completer();
      return tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStartupControllerProvider.overrideWith((_) => startup.future),
            splashControllerProvider.overrideWith(_Splash.new),
            libraryProgressProvider.overrideWith(_Library.new),
          ],
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: BootScreen(),
            ),
          ),
        ),
      );
    }

    Finder black() => find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == const Color(0xFF000000),
    );

    testWidgets('covers startup, then fills and fades away', (tester) async {
      await pump(tester);
      expect(black(), findsOneWidget);
      startup.complete();
      await tester.pump();
      expect(black(), findsOneWidget, reason: 'library still loading');
      _Splash.done.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(black(), findsNothing);
    });

    testWidgets('steps aside at once when startup fails', (tester) async {
      await pump(tester);
      startup.completeError(Exception('broken'));
      await tester.pump();
      await tester.pump();
      expect(black(), findsNothing);
    });

    testWidgets('steps aside when the library cannot load', (tester) async {
      await pump(tester);
      startup.complete();
      await tester.pump();
      _Splash.done.completeError(const AudioPermissionDeniedException());
      await tester.pump();
      await tester.pump();
      expect(black(), findsNothing);
    });

    testWidgets('never stays stuck when startup stalls', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 19));
      expect(black(), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(black(), findsNothing);
    });

    testWidgets('reduced motion leaves without animating', (tester) async {
      await pump(tester, reduceMotion: true);
      startup.complete();
      _Splash.done.complete();
      // Each stage resolves a frame after the one before; no animation runs.
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(black(), findsNothing);
    });
  });
}
