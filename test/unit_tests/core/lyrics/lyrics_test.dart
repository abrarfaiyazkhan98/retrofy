import 'dart:convert';

import 'package:classipod/core/lyrics/lyrics.dart';
import 'package:classipod/core/lyrics/lyrics_repository.dart';
import 'package:classipod/core/models/music_metadata.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MusicMetadata spotifyTrack({String? lyrics}) => MusicMetadata(
  songId: 'spotify:track:abc',
  trackName: 'Champagne In The Morning',
  trackArtistNames: const ['Redferrin'],
  albumName: 'Old No. 7',
  trackDuration: 160970,
  isOnDevice: false,
  lyrics: lyrics,
);

void main() {
  group('lrc_parser', () {
    test('reads timestamps, fractions and repeated lines', () {
      final lines = parseLrc(
        '[ar:Redferrin]\n'
        '[00:08.11] We watch that moon sink\n'
        '[00:12.5][01:02.005]Chorus\n'
        '[00:20]\n',
      );
      expect(lines, [
        const LyricLine(
          Duration(seconds: 8, milliseconds: 110),
          'We watch that moon sink',
        ),
        const LyricLine(Duration(seconds: 12, milliseconds: 500), 'Chorus'),
        const LyricLine(Duration(seconds: 20), ''),
        const LyricLine(
          Duration(minutes: 1, seconds: 2, milliseconds: 5),
          'Chorus',
        ),
      ]);
    });

    test('applies the offset tag, never before zero', () {
      final lines = parseLrc('[offset:+500]\n[00:00.20]a\n[00:02.00]b');
      expect(lines.map((line) => line.time), [
        Duration.zero,
        const Duration(milliseconds: 1500),
      ]);
    });

    test('text without timestamps stays plain', () {
      final lyrics = Lyrics.parse('Line one\nLine two', LyricsSource.embedded)!;
      expect(lyrics.isSynced, isFalse);
      expect(lyrics.plain, 'Line one\nLine two');
      expect(Lyrics.parse('  ', LyricsSource.embedded), isNull);
    });

    test('finds the line being sung', () {
      final lyrics = Lyrics.parse(
        '[00:01.00]a\n[00:05.00]b\n[00:09.00]c',
        LyricsSource.lrclib,
      )!;
      expect(lyrics.indexAt(Duration.zero), -1);
      expect(lyrics.indexAt(const Duration(seconds: 1)), 0);
      expect(lyrics.indexAt(const Duration(milliseconds: 8999)), 1);
      expect(lyrics.indexAt(const Duration(minutes: 3)), 2);
    });
  });

  group('lyrics_sources', () {
    late List<http.Request> requests;
    late http.Response Function() respond;

    ProviderContainer container({Future<String?> Function(String)? lrcFile}) {
      final c = ProviderContainer(
        overrides: [
          lrclibClientProvider.overrideWithValue(
            LrclibClient(
              wait: (_) async {},
              client: MockClient((request) async {
                requests.add(request);
                return respond();
              }),
            ),
          ),
          if (lrcFile != null) lrcFileReaderProvider.overrideWithValue(lrcFile),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<Lyrics?> read(ProviderContainer c, MusicMetadata track) async {
      final sub = c.listen(lyricsProvider(track), (_, _) {});
      addTearDown(sub.close);
      return c.read(lyricsProvider(track).future);
    }

    setUp(() {
      requests = [];
      respond = () => http.Response(
        jsonEncode({
          'instrumental': false,
          'syncedLyrics': '[00:08.11] We watch that moon sink',
          'plainLyrics': 'We watch that moon sink',
        }),
        200,
      );
    });

    test('Spotify tracks use LRCLIB with the track signature', () async {
      final lyrics = await read(container(), spotifyTrack());
      expect(lyrics!.source, LyricsSource.lrclib);
      expect(lyrics.lines.single.text, 'We watch that moon sink');
      final request = requests.single;
      expect(request.url.host, 'lrclib.net');
      expect(request.url.path, '/api/get');
      expect(request.url.queryParameters, {
        'track_name': 'Champagne In The Morning',
        'artist_name': 'Redferrin',
        'album_name': 'Old No. 7',
        'duration': '161',
      });
      expect(request.headers['User-Agent'], startsWith('Retrofy/'));
    });

    test('plain-only entries borrow a synced entry of the same length', () {
      // Good Life on Graduation: the exact entry is plain only; the single
      // with the same 3:27 length is synced, a live version is not used.
      respond = () {
        if (requests.last.url.path == '/api/get') {
          return http.Response(
            jsonEncode({'plainLyrics': 'Welcome to the good life'}),
            200,
          );
        }
        return http.Response(
          jsonEncode([
            {'duration': 286.0, 'syncedLyrics': '[00:01.00] live'},
            {'duration': 160.0, 'syncedLyrics': '[00:01.00] single'},
          ]),
          200,
        );
      };
      return read(container(), spotifyTrack()).then((lyrics) {
        expect(lyrics!.isSynced, isTrue);
        expect(lyrics.lines.single.text, 'single');
        expect(requests.last.url.path, '/api/search');
      });
    });

    test('plain lyrics stay when no synced entry matches', () async {
      respond = () => requests.last.url.path == '/api/get'
          ? http.Response(jsonEncode({'plainLyrics': 'just words'}), 200)
          : http.Response('[]', 200);
      final lyrics = await read(container(), spotifyTrack());
      expect(lyrics!.isSynced, isFalse);
      expect(lyrics.plain, 'just words');
    });

    test('a missing song is remembered for the session', () async {
      respond = () =>
          http.Response('{"name":"TrackNotFound","statusCode":404}', 404);
      final c = container();
      expect(await read(c, spotifyTrack()), isNull);
      c.invalidate(lyricsProvider(spotifyTrack()));
      expect(await read(c, spotifyTrack()), isNull);
      expect(requests, hasLength(1));
    });

    test('one retry after LRCLIB sheds load', () async {
      var calls = 0;
      respond = () => calls++ == 0
          ? http.Response('', 503, headers: {'retry-after': '1'})
          : http.Response(
              jsonEncode({'syncedLyrics': '[00:01.00]back again'}),
              200,
            );
      final lyrics = await read(container(), spotifyTrack());
      expect(lyrics!.lines.single.text, 'back again');
      expect(requests, hasLength(2));
    });

    test('instrumentals are flagged rather than shown empty', () async {
      respond = () => http.Response('{"instrumental":true}', 200);
      final lyrics = await read(container(), spotifyTrack());
      expect(lyrics!.instrumental, isTrue);
    });

    test('offline lookups show nothing and retry later', () async {
      respond = () => throw Exception('Failed host lookup');
      final c = container();
      expect(await read(c, spotifyTrack()), isNull);
      c.invalidate(lyricsProvider(spotifyTrack()));
      await read(c, spotifyTrack());
      expect(requests, hasLength(2));
    });

    test('synced embedded lyrics win without a network call', () async {
      final lyrics = await read(
        container(),
        spotifyTrack(lyrics: '[00:01.00]From tags'),
      );
      expect(lyrics!.source, LyricsSource.embedded);
      expect(requests, isEmpty);
    });

    test(
      'local tracks prefer a synced .lrc file and never use LRCLIB',
      () async {
        final local = MusicMetadata(
          songId: 'local',
          filePath: '/music/song.mp3',
          lyrics: 'plain words',
        );
        String? asked;
        final lyrics = await read(
          container(
            lrcFile: (path) async {
              asked = path;
              return '[00:02.00]synced words';
            },
          ),
          local,
        );
        expect(asked, '/music/song.mp3');
        expect(lyrics!.source, LyricsSource.lrcFile);
        expect(lyrics.isSynced, isTrue);
        expect(requests, isEmpty);

        final plainOnly = await read(
          container(lrcFile: (_) async => null),
          local.copyWith(songId: 'other'),
        );
        expect(plainOnly!.plain, 'plain words');
        expect(requests, isEmpty);
      },
    );
  });
}
