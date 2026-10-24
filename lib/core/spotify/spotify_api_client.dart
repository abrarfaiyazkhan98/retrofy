import 'dart:async';
import 'dart:convert';

import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef SpotifyAccessToken = Future<String> Function({bool forceRefresh});

class SpotifySearchResults {
  final List<MusicMetadata> tracks;
  final List<SpotifyAlbum> albums;
  final List<SpotifyArtist> artists;

  const SpotifySearchResults({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
  });

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}

/// Read-only Web API client limited to endpoints still available to
/// Development Mode apps after Spotify's February 2026 changes.
class SpotifyApiClient {
  final SpotifyAccessToken _token;
  final http.Client _http;
  final Future<void> Function(Duration) _wait;

  /// Large libraries are paged lazily by Spotify; cap what a list loads so a
  /// click-wheel list stays responsive and requests stay well under quota.
  static const maxListItems = 2000;
  static const _maxRetryAfter = Duration(seconds: 30);
  static final _base = Uri.https('api.spotify.com', '/v1/');

  SpotifyApiClient(
    this._token, {
    http.Client? client,
    Future<void> Function(Duration)? wait,
  }) : _http = client ?? http.Client(),
       _wait = wait ?? Future<void>.delayed;

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String> query = const {},
  ]) => _get(_base.resolve(path).replace(queryParameters: query));

  Future<Map<String, dynamic>> _get(Uri uri) async {
    var refreshed = false;
    var throttled = 0;
    while (true) {
      final token = await _token(forceRefresh: refreshed);
      final http.Response response;
      try {
        response = await _http
            .get(uri, headers: {'Authorization': 'Bearer $token'})
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        throw const SpotifyException('timeout');
      } catch (_) {
        throw const SpotifyException('connection');
      }
      if (response.statusCode != 200) {
        // Path and Spotify's error message only; never headers or tokens.
        debugPrint(
          'Spotify API ${uri.path} failed: HTTP ${response.statusCode} '
          '${utf8.decode(response.bodyBytes, allowMalformed: true).replaceAll('\n', ' ')}',
        );
      }
      switch (response.statusCode) {
        case 200:
          try {
            return jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>;
          } catch (_) {
            throw const SpotifyException('response');
          }
        case 401 when !refreshed:
          refreshed = true;
          continue;
        case 401:
          throw const SpotifyException('session_expired');
        case 429:
          final retryAfter = Duration(
            seconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 5,
          );
          if (throttled++ >= 2 || retryAfter > _maxRetryAfter) {
            throw const SpotifyException('rate_limited');
          }
          await _wait(retryAfter);
          continue;
        case 403:
          final body = utf8.decode(response.bodyBytes).toLowerCase();
          throw SpotifyException(
            body.contains('not be registered') ||
                    body.contains('not registered')
                ? 'user_not_registered'
                : 'forbidden',
          );
        case 404:
          throw const SpotifyException('not_found');
        default:
          throw const SpotifyException('server');
      }
    }
  }

  /// Follows `next` links. [unwrap] selects the paging object when the
  /// response nests it (e.g. `{"artists": {...}}`).
  Future<List<Object?>> _paged(
    String path,
    Map<String, String> query, {
    String? unwrap,
    int limit = maxListItems,
  }) async {
    final items = <Object?>[];
    Uri? next = _base.resolve(path).replace(queryParameters: query);
    while (next != null && items.length < limit) {
      final response = await _get(next);
      final page = unwrap == null ? response : response[unwrap];
      if (page is! Map) throw const SpotifyException('response');
      final pageItems = page['items'];
      if (pageItems is! List) throw const SpotifyException('response');
      items.addAll(pageItems);
      final link = page['next'];
      next = link is String && pageItems.isNotEmpty ? Uri.parse(link) : null;
      if (next != null && next.host != _base.host) {
        throw const SpotifyException('response');
      }
    }
    return items.length > limit ? items.sublist(0, limit) : items;
  }

  Future<SpotifyProfile> me() async {
    final profile = SpotifyProfile.fromJson(await get('me'));
    if (profile == null) throw const SpotifyException('response');
    return profile;
  }

  Future<List<SpotifyPlaylist>> playlists() async => [
    for (final item in await _paged('me/playlists', {'limit': '50'}))
      ?SpotifyPlaylist.fromJson(item),
  ];

  /// Lists the tracks of a playback context (playlist, album, Liked Songs)
  /// with the positions the Spotify app uses for them. With
  /// `market=from_token` the Web API marks tracks this account cannot play
  /// (e.g. not available in its country); the Spotify app leaves those out
  /// of the context, so they are dropped here and the tracks after them
  /// numbered as the app counts them. Otherwise every later row would start
  /// the track after it.
  List<MusicMetadata> _contextTracks(
    List<Object?> items,
    Object? Function(Object? entry) unwrap, {
    SpotifyAlbum? album,
  }) {
    final tracks = <MusicMetadata>[];
    var position = 0;
    for (final entry in items) {
      final item = unwrap(entry);
      if (item is Map && item['is_playable'] == false) {
        debugPrint('Spotify cannot play ${item['uri']} here; not listed');
        continue;
      }
      final track = spotifyTrackToMetadata(
        item,
        position: position++,
        album: album,
      );
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  static Object? _trackOf(Object? entry) =>
      entry is Map ? entry['item'] ?? entry['track'] : null;

  Future<List<MusicMetadata>> playlistTracks(String playlistId) async =>
      _contextTracks(
        await _paged('playlists/$playlistId/items', {
          'limit': '50',
          'additional_types': 'track',
          'market': 'from_token',
        }),
        _trackOf,
      );

  Future<List<MusicMetadata>> savedTracks() async => _contextTracks(
    await _paged('me/tracks', {'limit': '50', 'market': 'from_token'}),
    _trackOf,
  );

  /// Raw audio features (tempo, energy, valence) for up to 100 track IDs.
  /// Apps created after November 2024 get 403 here; callers must treat
  /// that as "no data", never as a reason to guess.
  Future<List<Object?>> audioFeatures(List<String> trackIds) async {
    final response = await get('audio-features', {'ids': trackIds.join(',')});
    final items = response['audio_features'];
    if (items is! List) throw const SpotifyException('response');
    return items;
  }

  /// How many Liked Songs the user has, from a one-item page.
  Future<int> savedTrackCount() async {
    final response = await get('me/tracks', {'limit': '1'});
    final total = response['total'];
    if (total is! int) throw const SpotifyException('response');
    return total;
  }

  Future<List<SpotifyAlbum>> savedAlbums() async => [
    for (final item in await _paged('me/albums', {'limit': '50'}))
      if (item case final Map entry) ?SpotifyAlbum.fromJson(entry['album']),
  ];

  Future<List<MusicMetadata>> albumTracks(SpotifyAlbum album) async =>
      _contextTracks(
        await _paged('albums/${album.id}/tracks', {
          'limit': '50',
          'market': 'from_token',
        }),
        (entry) => entry,
        album: album,
      );

  Future<List<SpotifyArtist>> followedArtists() async => [
    for (final item in await _paged('me/following', {
      'type': 'artist',
      'limit': '50',
    }, unwrap: 'artists'))
      ?SpotifyArtist.fromJson(item),
  ];

  Future<List<SpotifyAlbum>> artistAlbums(String artistId) async => [
    for (final item in await _paged('artists/$artistId/albums', {
      'include_groups': 'album,single,compilation',
      'limit': '50',
    }, limit: 200))
      ?SpotifyAlbum.fromJson(item),
  ];

  /// The artists credited on one track, with their Spotify IDs.
  Future<List<SpotifyArtist>> trackArtists(String trackId) async {
    final response = await get('tracks/$trackId');
    final artists = response['artists'];
    if (artists is! List) throw const SpotifyException('response');
    return [for (final artist in artists) ?SpotifyArtist.fromJson(artist)];
  }

  /// Recently played has no playing context, so positions are only for keys.
  Future<List<MusicMetadata>> recentlyPlayed() async {
    final response = await get('me/player/recently-played', {'limit': '50'});
    final items = response['items'];
    if (items is! List) throw const SpotifyException('response');
    final seen = <String>{};
    return [
      for (var i = 0; i < items.length; i++)
        if (items[i] case final Map entry)
          if (spotifyTrackToMetadata(entry['track'], position: i)
              case final track? when seen.add(track.identity))
            track,
    ];
  }

  /// Search returns at most 10 results per type for Development Mode apps.
  Future<SpotifySearchResults> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const SpotifySearchResults();
    final response = await get('search', {
      'q': trimmed,
      'type': 'track,album,artist',
      'limit': '10',
      'market': 'from_token',
    });
    List<Object?> items(String key) {
      final page = response[key];
      return page is Map && page['items'] is List
          ? page['items'] as List
          : const [];
    }

    // Search results play on their own, so unplayable ones are dropped.
    final tracks = [
      for (final item in items('tracks'))
        if (item is! Map || item['is_playable'] != false) item,
    ];
    return SpotifySearchResults(
      tracks: [
        for (var i = 0; i < tracks.length; i++)
          ?spotifyTrackToMetadata(tracks[i], position: i),
      ],
      albums: [
        for (final item in items('albums')) ?SpotifyAlbum.fromJson(item),
      ],
      artists: [
        for (final item in items('artists')) ?SpotifyArtist.fromJson(item),
      ],
    );
  }

  void close() => _http.close();
}
