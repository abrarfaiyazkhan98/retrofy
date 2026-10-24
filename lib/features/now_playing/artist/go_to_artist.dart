import 'package:classipod/core/models/music_metadata.dart';
import 'package:classipod/core/spotify/spotify_auth_controller.dart';
import 'package:classipod/core/spotify/spotify_playback_controller.dart';
import 'package:classipod/core/spotify/spotify_remote.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// One artist credited on the playing Spotify track, identified by its
/// Spotify ID rather than its name.
@immutable
class ArtistLink {
  final String name;
  final String id;

  const ArtistLink({required this.name, required this.id});

  static final _id = RegExp(r'^[0-9A-Za-z]{22}$');

  /// Parses `spotify:artist:<id>`; null for anything else.
  static ArtistLink? fromUri(String name, String? uri) {
    const prefix = 'spotify:artist:';
    if (uri == null || !uri.startsWith(prefix)) return null;
    final id = uri.substring(prefix.length);
    return _id.hasMatch(id) ? ArtistLink(name: name, id: id) : null;
  }

  /// Opens the artist in the Spotify app.
  Uri get appUri => Uri.parse('spotify:artist:$id');

  /// The official artist page, for when the Spotify app is not installed.
  Uri get webUri => Uri.https('open.spotify.com', '/artist/$id');

  @override
  bool operator ==(Object other) =>
      other is ArtistLink && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Artists of [track] as the Spotify app reports them in [player], when the
/// player is on that track. Empty when it is not a match.
List<ArtistLink> artistLinksFromPlayer(
  MusicMetadata? track,
  SpotifyPlayerState? player,
) {
  if (track == null ||
      !track.isSpotify ||
      player == null ||
      player.trackUri != track.songId) {
    return const [];
  }
  final links = <ArtistLink>[];
  for (var i = 0; i < player.artists.length; i++) {
    final uri = i < player.artistUris.length ? player.artistUris[i] : null;
    final link = ArtistLink.fromUri(player.artists[i], uri);
    if (link != null && !links.contains(link)) links.add(link);
  }
  return links;
}

/// Artists of the track in Now Playing. Spotify's live player state is used
/// first (no network); otherwise the track is looked up once in the Web API.
/// Local and Subsonic tracks have no Spotify artist and give an empty list.
final currentArtistLinksProvider = FutureProvider.autoDispose<List<ArtistLink>>(
  (ref) async {
    final track = ref.watch(
      nowPlayingDetailsProvider.select((value) => value.currentMetadata),
    );
    if (track == null || !track.isSpotify) return const [];
    final fromPlayer = artistLinksFromPlayer(
      track,
      ref.read(spotifyPlaybackControllerProvider).player,
    );
    if (fromPlayer.isNotEmpty) return fromPlayer;
    final trackId = track.songId!.split(':').last;
    final artists = await ref.read(spotifyApiProvider).trackArtists(trackId);
    return [
      for (final artist in artists)
        ?ArtistLink.fromUri(artist.name, artist.uri),
    ];
  },
);

typedef UrlOpener = Future<bool> Function(Uri uri);

/// Opens [link] in the Spotify app, or its web page in the browser when the
/// app is missing. Returns false only if neither could be opened.
Future<bool> openArtistLink(ArtistLink link, UrlOpener open) async {
  try {
    if (await open(link.appUri)) return true;
  } catch (_) {
    // No app handles spotify: links; fall through to the web page.
  }
  try {
    return await open(link.webUri);
  } catch (_) {
    return false;
  }
}

final urlOpenerProvider = Provider<UrlOpener>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
