import 'package:classipod/core/models/music_metadata.dart';

/// Picks an image near [target] pixels wide; Spotify lists widest first.
/// The default targets Spotify's largest (640 px) cover so Now Playing stays
/// sharp full-screen; list rows decode it at their own small size.
String? spotifyImageUrl(Object? images, {int target = 640}) {
  if (images is! List || images.isEmpty) return null;
  final candidates = images
      .whereType<Map>()
      .where((image) => image['url'] is String)
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort(
    (a, b) => ((a['width'] as int?) ?? 0).compareTo((b['width'] as int?) ?? 0),
  );
  for (final image in candidates) {
    if (((image['width'] as int?) ?? 0) >= target) {
      return image['url'] as String;
    }
  }
  return candidates.last['url'] as String;
}

/// App Remote reports artwork as `spotify:image:<id>`, served by the same CDN
/// the Web API image URLs use.
String? spotifyImageUriToUrl(String? raw) {
  const prefix = 'spotify:image:';
  if (raw == null || !raw.startsWith(prefix)) return null;
  final id = raw.substring(prefix.length);
  if (!RegExp(r'^[0-9a-zA-Z]+$').hasMatch(id)) return null;
  return 'https://i.scdn.co/image/$id';
}

List<String> _artistNames(Object? artists) => [
  if (artists is List)
    for (final artist in artists.whereType<Map>())
      if (artist['name'] is String) artist['name'] as String,
];

int? _year(Object? releaseDate) =>
    releaseDate is String && releaseDate.length >= 4
    ? int.tryParse(releaseDate.substring(0, 4))
    : null;

class SpotifyAlbum {
  final String id;
  final String uri;
  final String name;
  final List<String> artists;
  final String? imageUrl;
  final int? year;

  const SpotifyAlbum({
    required this.id,
    required this.uri,
    required this.name,
    required this.artists,
    this.imageUrl,
    this.year,
  });

  String get artistLine => artists.join(', ');

  static SpotifyAlbum? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final uri = json['uri'];
    if (id is! String || uri is! String) return null;
    return SpotifyAlbum(
      id: id,
      uri: uri,
      name: json['name'] as String? ?? '',
      artists: _artistNames(json['artists']),
      imageUrl: spotifyImageUrl(json['images']),
      year: _year(json['release_date']),
    );
  }

  @override
  bool operator ==(Object other) => other is SpotifyAlbum && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

class SpotifyArtist {
  final String id;
  final String uri;
  final String name;
  final String? imageUrl;

  const SpotifyArtist({
    required this.id,
    required this.uri,
    required this.name,
    this.imageUrl,
  });

  static SpotifyArtist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final uri = json['uri'];
    if (id is! String || uri is! String) return null;
    return SpotifyArtist(
      id: id,
      uri: uri,
      name: json['name'] as String? ?? '',
      imageUrl: spotifyImageUrl(json['images']),
    );
  }

  @override
  bool operator ==(Object other) => other is SpotifyArtist && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

class SpotifyPlaylist {
  final String id;
  final String uri;
  final String name;
  final String? ownerId;
  final bool collaborative;
  final String? imageUrl;

  const SpotifyPlaylist({
    required this.id,
    required this.uri,
    required this.name,
    this.ownerId,
    this.collaborative = false,
    this.imageUrl,
  });

  /// Development Mode apps may only list items of playlists the user owns or
  /// collaborates on; others can still be played as a whole by URI.
  bool canListItems(String? userId) =>
      collaborative || (userId != null && ownerId == userId);

  static SpotifyPlaylist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final uri = json['uri'];
    if (id is! String || uri is! String) return null;
    final owner = json['owner'];
    return SpotifyPlaylist(
      id: id,
      uri: uri,
      name: json['name'] as String? ?? '',
      ownerId: owner is Map ? owner['id'] as String? : null,
      collaborative: json['collaborative'] == true,
      imageUrl: spotifyImageUrl(json['images']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpotifyPlaylist && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

class SpotifyProfile {
  final String id;
  final String displayName;

  const SpotifyProfile({required this.id, required this.displayName});

  static SpotifyProfile? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final id = json['id'] as String;
    return SpotifyProfile(
      id: id,
      displayName: json['display_name'] as String? ?? id,
    );
  }
}

/// Spotify tracks reuse the app's track model so lists, Now Playing and Cover
/// Flow render them unchanged. [position] is the index inside the playing
/// context, which App Remote needs to start at that track.
MusicMetadata? spotifyTrackToMetadata(
  Object? json, {
  required int position,
  SpotifyAlbum? album,
}) {
  if (json is! Map) return null;
  final uri = json['uri'];
  if (uri is! String ||
      !uri.startsWith('spotify:track:') ||
      json['is_local'] == true) {
    return null;
  }
  final albumJson = json['album'];
  final trackAlbum = SpotifyAlbum.fromJson(albumJson) ?? album;
  final artists = _artistNames(json['artists']);
  return MusicMetadata(
    songId: uri,
    trackName: json['name'] as String?,
    trackArtistNames: artists.isEmpty ? null : artists,
    albumName: trackAlbum?.name,
    albumArtistName: trackAlbum?.artistLine,
    albumArtistNames: trackAlbum?.artists,
    trackNumber: json['track_number'] as int?,
    discNumber: json['disc_number'] as int?,
    trackDuration: json['duration_ms'] as int?,
    year: trackAlbum?.year,
    thumbnailPath: trackAlbum?.imageUrl,
    originalSongIndex: position,
    isOnDevice: false,
  );
}
