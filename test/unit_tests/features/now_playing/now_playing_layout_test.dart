import 'dart:math' as math;
import 'dart:typed_data';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/core/theme/artwork_palette.dart';
import 'package:classipod/features/now_playing/artist/go_to_artist.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_artwork_scene.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_widget.dart';
import 'package:classipod/features/now_playing/widgets/synced_lyrics_view.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('now_playing_geometry', () {
    test('a phone display puts a compact cover beside the title', () {
      const window = Size(365, 590);
      final g = NowPlayingGeometry.of(window);
      expect(g.sideBySide, isFalse);
      expect(g.titleBesideArtwork, isTrue);
      // Smaller than the old full-width cover, still clearly the subject.
      expect(g.artworkSize, inInclusiveRange(365 * 0.45, 365 * 0.6));
      expect(
        g.lyricsHeight,
        greaterThanOrEqualTo(window.height * 0.45),
        reason: 'lyrics take about half the display',
      );
    });

    test('a half-height split-screen window shrinks the cover', () {
      const window = Size(365, 300);
      final g = NowPlayingGeometry.of(window);
      expect(g.artworkSize, lessThan(365 * 0.45));
      expect(
        g.lyricsHeight,
        greaterThanOrEqualTo(NowPlayingPanel.minLyricsHeight),
        reason: 'split screen still shows a few lyric lines',
      );
    });

    test('a very short window drops the cover, never the controls', () {
      final g = NowPlayingGeometry.of(const Size(300, 180));
      expect(g.artworkSize, 0);
      expect(g.compactMetadata, isTrue);
    });

    test('very narrow displays stack the cover above the title', () {
      final g = NowPlayingGeometry.of(const Size(240, 400));
      expect(g.titleBesideArtwork, isFalse);
      expect(g.sideBySide, isFalse);
      expect(g.artworkSize, greaterThan(0));
    });

    test('tablet displays cap the cover', () {
      final g = NowPlayingGeometry.of(const Size(800, 1000));
      expect(g.artworkSize, NowPlayingGeometry.maxArtwork);
    });

    test('wide, short windows put the cover beside the panel', () {
      final g = NowPlayingGeometry.of(const Size(430, 260));
      expect(g.sideBySide, isTrue);
      expect(g.artworkSize, lessThanOrEqualTo(260));
      expect(430 - g.artworkSize, greaterThanOrEqualTo(430 * 0.55 - 0.001));
    });

    for (final size in const [
      Size(240, 400),
      Size(320, 220),
      Size(365, 260),
      Size(365, 420),
      Size(365, 590),
      Size(412, 700),
      Size(450, 300),
      Size(700, 300),
      Size(800, 1000),
      Size(1200, 700),
    ]) {
      test('cover, title and controls fit in $size', () {
        final g = NowPlayingGeometry.of(size);
        const insets = NowPlayingGeometry.topInset + NowPlayingGeometry.inset;
        expect(
          g.headerHeight + insets + NowPlayingGeometry.controlsHeight,
          lessThanOrEqualTo(size.height),
        );
        expect(
          g.lyricsHeight,
          closeTo(
            size.height -
                insets -
                g.headerHeight -
                NowPlayingGeometry.controlsHeight,
            0.001,
          ),
        );
        if (g.sideBySide) {
          expect(g.artworkSize, lessThanOrEqualTo(size.height));
          expect(
            size.width - g.artworkSize,
            greaterThanOrEqualTo(NowPlayingGeometry.panelMinWidth),
          );
        } else if (g.titleBesideArtwork) {
          expect(
            size.width - g.artworkSize - 3 * NowPlayingGeometry.inset,
            greaterThanOrEqualTo(NowPlayingGeometry.metadataMinWidth),
          );
        } else {
          expect(g.artworkSize, lessThanOrEqualTo(size.width));
        }
      });
    }
  });

  group('album_color_panel', () {
    test('the panel stays dark and readable for any cover', () {
      for (final scrim in const [
        Color(0xFF15171C),
        Color(0xFF3A3A08),
        Color(0xFF00FF00),
        Color(0xFFFFFFFF),
        Color(0xFF000000),
        Color(0xFF1B2A4A),
      ]) {
        final palette = ArtworkPalette(
          scrim: scrim,
          accent: const Color(0xFF6FB3FF),
          primary: scrim,
          secondary: scrim,
        );
        final panel = palette.panel;
        final hsl = HSLColor.fromColor(panel);
        // 8-bit colour rounding moves saturation slightly.
        expect(hsl.saturation, lessThanOrEqualTo(0.34));
        expect(hsl.lightness, inInclusiveRange(0.125, 0.185));
        final contrast = 1.05 / (panel.computeLuminance() + 0.05);
        expect(contrast, greaterThanOrEqualTo(7), reason: '$scrim');
      }
    });

    /// Contrast of white at [alpha] laid over [glass] over [backdrop].
    double contrast(double alpha, Color backdrop, [Color? glass]) {
      final bg = glass == null ? backdrop : Color.alphaBlend(glass, backdrop);
      final fg = Color.alphaBlend(
        const Color(0xFFFFFFFF).withValues(alpha: alpha),
        bg,
      );
      final a = fg.computeLuminance(), b = bg.computeLuminance();
      return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
    }

    final covers = <String, Color>{
      'white': const Color(0xFFFFFFFF),
      'black': const Color(0xFF000000),
      'yellow': const Color(0xFFFFE600),
      'lime': const Color(0xFF00FF00),
      'cyan': const Color(0xFF00FFFF),
      'red': const Color(0xFFDC1428),
      'grey': const Color(0xFF808080),
    };
    for (final entry in covers.entries) {
      test('text over a ${entry.key} cover backdrop stays readable', () {
        final c = entry.value;
        final palette = ArtworkPalette(
          scrim: c,
          accent: const Color(0xFF6FB3FF),
          primary: c,
          secondary: c,
        );
        for (final backdrop in [palette.ambient, palette.depth]) {
          expect(contrast(1, backdrop), greaterThanOrEqualTo(7));
          expect(
            contrast(NowPlayingMetadata.secondaryAlpha, backdrop),
            greaterThanOrEqualTo(4.5),
            reason: 'artist',
          );
          expect(
            contrast(NowPlayingMetadata.tertiaryAlpha, backdrop),
            greaterThanOrEqualTo(4.5),
            reason: 'album and timestamps',
          );
          // Lyrics sit on the glass surface.
          expect(
            contrast(1, backdrop, palette.glass),
            greaterThanOrEqualTo(7),
            reason: 'sung line',
          );
          expect(
            contrast(
              SyncedLyricsViewState.upcomingAlpha,
              backdrop,
              palette.glass,
            ),
            greaterThanOrEqualTo(4.5),
            reason: 'upcoming lines',
          );
          expect(
            contrast(SyncedLyricsViewState.sungAlpha, backdrop, palette.glass),
            greaterThanOrEqualTo(3),
            reason: 'past lines are dimmed but legible',
          );
        }
      });
    }

    test('the backdrop is darker at the bottom than at the top', () {
      final palette = ArtworkPalette.fromPixels(
        Uint8List.fromList([
          for (var i = 0; i < 16; i++) ...[40, 90, 200, 255],
        ]),
      );
      expect(
        palette.depth.computeLuminance(),
        lessThan(palette.ambient.computeLuminance()),
      );
      expect(HSLColor.fromColor(palette.ambient).hue, closeTo(222, 6));
    });

    test('a dark blue cover gives a dark blue panel', () {
      final palette = ArtworkPalette(
        scrim: const HSLColor.fromAHSL(1, 220, 0.4, 0.12).toColor(),
        accent: const Color(0xFF6FB3FF),
        primary: const Color(0xFF2E4A6E),
        secondary: const Color(0xFF2E4A6E),
      );
      final hsl = HSLColor.fromColor(palette.panel);
      expect(hsl.hue, closeTo(220, 1));
    });
  });

  group('artist_navigation', () {
    const stereoHearts = 'spotify:track:0qOnSQQF0yzuPWsXrQ9paz';
    const gch = 'spotify:artist:4IJczjB0fJ04gs4uvP0Fli';
    const adam = 'spotify:artist:4bYPcJP5jwMhSivRcqie2n';
    final track = MusicMetadata(songId: stereoHearts, isOnDevice: false);

    SpotifyPlayerState player({
      String trackUri = stereoHearts,
      List<String> artists = const ['Gym Class Heroes', 'Adam Levine'],
      List<String?> uris = const [gch, adam],
    }) => SpotifyPlayerState(
      trackUri: trackUri,
      artists: artists,
      artistUris: uris,
      receivedAt: DateTime(2026),
    );

    test('every credited artist is linked by its Spotify ID', () {
      final links = artistLinksFromPlayer(track, player());
      expect(links.map((l) => l.name), ['Gym Class Heroes', 'Adam Levine']);
      expect(links.first.id, '4IJczjB0fJ04gs4uvP0Fli');
      expect(links.first.appUri.toString(), gch);
      expect(
        links.first.webUri.toString(),
        'https://open.spotify.com/artist/4IJczjB0fJ04gs4uvP0Fli',
      );
    });

    test('a player on another track is not used', () {
      expect(
        artistLinksFromPlayer(
          track,
          player(trackUri: 'spotify:track:7J9pu2h4j18XsoWC5ZqQ4z'),
        ),
        isEmpty,
      );
    });

    test('artists without an ID are left out, never searched by name', () {
      final links = artistLinksFromPlayer(
        track,
        player(uris: const [null, adam]),
      );
      expect(links.single.name, 'Adam Levine');
    });

    test('library tracks have no Spotify artist', () {
      final local = MusicMetadata(songId: '/music/a.mp3');
      expect(artistLinksFromPlayer(local, player()), isEmpty);
    });

    test('malformed artist URIs are rejected', () {
      expect(ArtistLink.fromUri('X', 'spotify:artist:../../evil'), isNull);
      expect(
        ArtistLink.fromUri('X', 'spotify:album:4IJczjB0fJ04gs4uvP0Fli'),
        isNull,
      );
    });

    test(
      'the Spotify app is preferred, the web page is the fallback',
      () async {
        const link = ArtistLink(
          name: 'Adam Levine',
          id: '4bYPcJP5jwMhSivRcqie2n',
        );
        final opened = <Uri>[];
        expect(
          await openArtistLink(link, (uri) async {
            opened.add(uri);
            return true;
          }),
          isTrue,
        );
        expect(opened, [link.appUri]);

        opened.clear();
        expect(
          await openArtistLink(link, (uri) async {
            opened.add(uri);
            return uri.scheme == 'https';
          }),
          isTrue,
        );
        expect(opened, [link.appUri, link.webUri]);

        opened.clear();
        expect(
          await openArtistLink(link, (uri) async {
            opened.add(uri);
            if (uri.scheme == 'spotify') throw Exception('no activity');
            return true;
          }),
          isTrue,
        );
        expect(opened, [link.appUri, link.webUri]);

        expect(await openArtistLink(link, (_) async => false), isFalse);
      },
    );

    test('player state carries artist URIs from the Spotify app', () {
      final state = SpotifyPlayerState.fromMap({
        'trackUri': stereoHearts,
        'artists': ['Gym Class Heroes', 'Adam Levine'],
        'artistUris': [gch, adam],
      }, DateTime(2026));
      expect(state.artistUris, [gch, adam]);
      final legacy = SpotifyPlayerState.fromMap({
        'trackUri': stereoHearts,
        'artists': ['Gym Class Heroes'],
      }, DateTime(2026));
      expect(legacy.artistUris, [null]);
    });
  });
}
