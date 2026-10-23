import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:classipod/features/now_playing/models/now_playing_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// A list of Spotify tracks and, when it has one, the Spotify context it
/// belongs to. Playing inside a context lets Spotify continue through it.
class SpotifyTrackSource {
  final String title;
  final ProviderListenable<AsyncValue<List<MusicMetadata>>> tracks;
  final String? contextUri;
  final NowPlayingType nowPlayingType;

  const SpotifyTrackSource({
    required this.title,
    required this.tracks,
    this.contextUri,
    this.nowPlayingType = NowPlayingType.songs,
  });
}

/// What a Spotify browse list shows: the user's playlists, saved albums,
/// followed artists, or one artist's albums.
class SpotifyBrowseSource {
  final SpotifyArtist? artist;
  final _SpotifyBrowseKind _kind;

  const SpotifyBrowseSource.playlists()
    : _kind = _SpotifyBrowseKind.playlists,
      artist = null;

  const SpotifyBrowseSource.savedAlbums()
    : _kind = _SpotifyBrowseKind.albums,
      artist = null;

  const SpotifyBrowseSource.artists()
    : _kind = _SpotifyBrowseKind.artists,
      artist = null;

  const SpotifyBrowseSource.artistAlbums(SpotifyArtist this.artist)
    : _kind = _SpotifyBrowseKind.albums;

  bool get isPlaylists => _kind == _SpotifyBrowseKind.playlists;

  bool get isArtists => _kind == _SpotifyBrowseKind.artists;
}

enum _SpotifyBrowseKind { playlists, albums, artists }
