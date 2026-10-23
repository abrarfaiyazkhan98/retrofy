import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which engine owns the Now Playing queue. Local files and Subsonic play
/// through `LibraryAudioHandler`; Spotify plays inside the Spotify app.
enum PlaybackBackend { library, spotify }

final playbackBackendProvider =
    NotifierProvider<PlaybackBackendNotifier, PlaybackBackend>(
      PlaybackBackendNotifier.new,
    );

class PlaybackBackendNotifier extends Notifier<PlaybackBackend> {
  @override
  PlaybackBackend build() => PlaybackBackend.library;

  set backend(PlaybackBackend backend) => state = backend;
}
