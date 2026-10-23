import 'package:classipod/core/models/music_metadata.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// A YouTube search for the track's official video. Nothing is fetched or
/// played until the user picks a result in YouTube; the YouTube app opens
/// it when installed, otherwise the browser does.
Uri? musicVideoSearchUri(MusicMetadata? track) {
  final title = track?.trackName?.trim();
  if (title == null || title.isEmpty) return null;
  final artist = track?.trackArtistNames?.firstOrNull?.trim();
  return Uri.https('www.youtube.com', '/results', {
    'search_query': [
      if (artist != null && artist.isNotEmpty) artist,
      title,
      'official video',
    ].join(' '),
  });
}

final musicVideoLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
