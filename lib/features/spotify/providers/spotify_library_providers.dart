import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/spotify/spotify_api_client.dart';
import 'package:classipod/core/spotify/spotify_auth.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every library request is scoped to the signed-in session: watching the
/// sign-in flag drops cached results as soon as the user signs out.
SpotifyApiClient _api(Ref ref) {
  final signedIn = ref.watch(
    spotifyAuthControllerProvider.select((value) => value.value?.signedIn),
  );
  if (signedIn != true) throw const SpotifyException('signin');
  return ref.read(spotifyApiProvider);
}

final spotifyPlaylistsProvider = FutureProvider<List<SpotifyPlaylist>>(
  (ref) => _api(ref).playlists(),
);

final spotifyPlaylistTracksProvider = FutureProvider.autoDispose
    .family<List<MusicMetadata>, String>(
      (ref, playlistId) => _api(ref).playlistTracks(playlistId),
    );

/// Stands in for playlists whose items Spotify will not list to this app.
final spotifyNoTracksProvider = Provider<AsyncValue<List<MusicMetadata>>>(
  (_) => const AsyncData([]),
);

final spotifySavedAlbumsProvider = FutureProvider<List<SpotifyAlbum>>(
  (ref) => _api(ref).savedAlbums(),
);

final spotifyAlbumTracksProvider = FutureProvider.autoDispose
    .family<List<MusicMetadata>, SpotifyAlbum>(
      (ref, album) => _api(ref).albumTracks(album),
    );

final spotifyFollowedArtistsProvider = FutureProvider<List<SpotifyArtist>>(
  (ref) => _api(ref).followedArtists(),
);

final spotifyArtistAlbumsProvider = FutureProvider.autoDispose
    .family<List<SpotifyAlbum>, String>(
      (ref, artistId) => _api(ref).artistAlbums(artistId),
    );

final spotifyLikedSongsProvider = FutureProvider<List<MusicMetadata>>(
  (ref) => _api(ref).savedTracks(),
);

final spotifyRecentlyPlayedProvider =
    FutureProvider.autoDispose<List<MusicMetadata>>(
      (ref) => _api(ref).recentlyPlayed(),
    );

final spotifySearchProvider = FutureProvider.autoDispose
    .family<SpotifySearchResults, String>(
      (ref, query) => _api(ref).search(query),
    );
