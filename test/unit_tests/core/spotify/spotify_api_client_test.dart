import 'dart:convert';

import 'package:classipod/core/spotify/spotify_api_client.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> track(String id, {Map<String, dynamic>? album}) => {
  'uri': 'spotify:track:$id',
  'name': 'Track $id',
  'duration_ms': 1000,
  'track_number': 1,
  'artists': [
    {'name': 'Artist'},
  ],
  'album': ?album,
};

void main() {
  late List<http.Request> requests;
  late List<http.Response> responses;
  late List<bool> refreshes;
  late List<Duration> waits;

  SpotifyApiClient client() => SpotifyApiClient(
    ({forceRefresh = false}) async {
      refreshes.add(forceRefresh);
      return forceRefresh ? 'fresh' : 'stale';
    },
    wait: (duration) async => waits.add(duration),
    client: MockClient((request) async {
      requests.add(request);
      return responses.removeAt(0);
    }),
  );

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<String> errorCode(Future<void> Function() call) async {
    try {
      await call();
    } on SpotifyException catch (error) {
      return error.code;
    }
    return 'none';
  }

  setUp(() {
    requests = [];
    responses = [];
    refreshes = [];
    waits = [];
  });

  group('errors', () {
    test('refreshes once on 401 and retries with the new token', () async {
      responses = [
        http.Response('', 401),
        json({'id': 'me', 'display_name': 'Me'}),
      ];
      final profile = await client().me();
      expect(profile.displayName, 'Me');
      expect(refreshes, [false, true]);
      expect(requests.last.headers['Authorization'], 'Bearer fresh');
    });

    test('reports an expired session when refresh does not help', () async {
      responses = [http.Response('', 401), http.Response('', 401)];
      expect(await errorCode(() => client().me()), 'session_expired');
    });

    test('honours Retry-After for short rate limits', () async {
      responses = [
        http.Response('', 429, headers: {'retry-after': '2'}),
        json({'id': 'me'}),
      ];
      await client().me();
      expect(waits, [const Duration(seconds: 2)]);
    });

    test('gives up on long or repeated rate limits', () async {
      responses = [
        http.Response('', 429, headers: {'retry-after': '3600'}),
      ];
      expect(await errorCode(() => client().me()), 'rate_limited');
      expect(waits, isEmpty);
    });

    test('explains Development Mode user allowlist rejections', () async {
      responses = [
        http.Response(
          '{"error":{"status":403,"message":"Check settings on '
          'developer.spotify.com/dashboard, the user may not be registered."}}',
          403,
        ),
      ];
      expect(await errorCode(() => client().me()), 'user_not_registered');
      responses = [http.Response('{}', 403)];
      expect(await errorCode(() => client().me()), 'forbidden');
      responses = [http.Response('{}', 404)];
      expect(await errorCode(() => client().me()), 'not_found');
      responses = [http.Response('{}', 502)];
      expect(await errorCode(() => client().me()), 'server');
    });

    test('reports offline requests as connection errors', () async {
      final offline = SpotifyApiClient(
        ({forceRefresh = false}) async => 'token',
        client: MockClient((_) => throw Exception('Failed host lookup')),
      );
      expect(await errorCode(offline.me), 'connection');
    });
  });

  group('library', () {
    test('pages playlists by following next links', () async {
      responses = [
        json({
          'items': [
            {'id': 'a', 'uri': 'spotify:playlist:a', 'name': 'A'},
          ],
          'next': 'https://api.spotify.com/v1/me/playlists?offset=1&limit=50',
        }),
        json({
          'items': [
            {
              'id': 'b',
              'uri': 'spotify:playlist:b',
              'name': 'B',
              'owner': {'id': 'me'},
            },
          ],
          'next': null,
        }),
      ];
      final playlists = await client().playlists();
      expect(playlists.map((p) => p.name), ['A', 'B']);
      expect(requests.first.url.path, '/v1/me/playlists');
      expect(requests.last.url.queryParameters['offset'], '1');
      expect(playlists.last.canListItems('me'), isTrue);
      expect(playlists.first.canListItems('me'), isFalse);
    });

    test('refuses next links to other hosts', () async {
      responses = [
        json({
          'items': [{}],
          'next': 'https://evil.example/steal',
        }),
      ];
      expect(await errorCode(() => client().playlists()), 'response');
    });

    test(
      'reads the renamed playlist items endpoint and keeps positions',
      () async {
        responses = [
          json({
            'items': [
              {'item': track('one')},
              {
                'item': {'uri': 'spotify:local:x', 'is_local': true},
              },
              {'track': track('three')},
            ],
          }),
        ];
        final tracks = await client().playlistTracks('pl');
        expect(requests.single.url.path, '/v1/playlists/pl/items');
        expect(tracks.map((t) => t.songId), [
          'spotify:track:one',
          'spotify:track:three',
        ]);
        // Positions index the playlist context, including skipped local files.
        expect(tracks.map((t) => t.originalSongIndex), [0, 2]);
        expect(tracks.every((t) => t.isSpotify && !t.isOnDevice), isTrue);
      },
    );

    test('album tracks inherit album name and artwork', () async {
      const album = SpotifyAlbum(
        id: 'al',
        uri: 'spotify:album:al',
        name: 'Album',
        artists: ['Band'],
        imageUrl: 'https://i.scdn.co/image/cover',
        year: 2001,
      );
      responses = [
        json({
          'items': [track('one')],
        }),
      ];
      final tracks = await client().albumTracks(album);
      expect(tracks.single.albumName, 'Album');
      expect(tracks.single.thumbnailPath, 'https://i.scdn.co/image/cover');
      expect(tracks.single.year, 2001);
    });

    test('followed artists unwrap the cursor page', () async {
      responses = [
        json({
          'artists': {
            'items': [
              {'id': 'x', 'uri': 'spotify:artist:x', 'name': 'X'},
            ],
            'next': null,
          },
        }),
      ];
      final artists = await client().followedArtists();
      expect(artists.single.name, 'X');
      expect(requests.single.url.queryParameters['type'], 'artist');
    });

    test('recently played drops repeats', () async {
      responses = [
        json({
          'items': [
            {'track': track('a')},
            {'track': track('a')},
            {'track': track('b')},
          ],
        }),
      ];
      final tracks = await client().recentlyPlayed();
      expect(tracks.map((t) => t.songId), [
        'spotify:track:a',
        'spotify:track:b',
      ]);
    });

    test('search stays within the Development Mode limit of 10', () async {
      responses = [
        json({
          'tracks': {
            'items': [
              track(
                't',
                album: {
                  'id': 'al',
                  'uri': 'spotify:album:al',
                  'name': 'Al',
                  'images': [
                    {'url': 'https://i.scdn.co/image/big', 'width': 640},
                    {'url': 'https://i.scdn.co/image/mid', 'width': 300},
                    {'url': 'https://i.scdn.co/image/small', 'width': 64},
                  ],
                },
              ),
            ],
          },
          'albums': {'items': []},
          'artists': {
            'items': [
              {'id': 'ar', 'uri': 'spotify:artist:ar', 'name': 'Ar'},
            ],
          },
        }),
      ];
      final results = await client().search('  daft punk ');
      expect(requests.single.url.queryParameters['limit'], '10');
      expect(requests.single.url.queryParameters['q'], 'daft punk');
      expect(
        results.tracks.single.thumbnailPath,
        'https://i.scdn.co/image/big',
      );
      expect(results.artists.single.name, 'Ar');
      expect(await client().search('   '), isA<SpotifySearchResults>());
      expect(requests, hasLength(1));
    });
  });

  test('maps App Remote image ids to CDN urls', () {
    expect(
      spotifyImageUriToUrl('spotify:image:ab67616d0000b273'),
      'https://i.scdn.co/image/ab67616d0000b273',
    );
    expect(spotifyImageUriToUrl('spotify:image:../x'), isNull);
    expect(spotifyImageUriToUrl(null), isNull);
  });
}
