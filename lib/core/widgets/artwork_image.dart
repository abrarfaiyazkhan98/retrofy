import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/spotify/spotify_artwork_cache.dart';
import 'package:classipod/core/subsonic/subsonic_controller.dart';
import 'package:classipod/core/widgets/artwork_file_stub.dart'
    if (dart.library.io) 'package:classipod/core/widgets/artwork_file_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final remoteArtworkProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, path) async {
      ref.watch(
        subsonicControllerProvider.select(
          (value) => (
            value.value?.enabled,
            value.value?.signedIn,
            value.value?.config?.id,
            value.value?.scanning,
          ),
        ),
      );
      return ref.read(subsonicControllerProvider.notifier).artwork(path);
    });

/// [decodeSize] decodes large covers at that many physical pixels, for rows
/// that show artwork small.
ImageProvider artworkImage(WidgetRef ref, String? path, {int? decodeSize}) {
  final image = _artworkImage(ref, path);
  return decodeSize == null
      ? image
      : ResizeImage.resizeIfNeeded(decodeSize, null, image);
}

ImageProvider _artworkImage(WidgetRef ref, String? path) {
  const fallback = AssetImage(Assets.defaultAlbumCoverImage);
  if (path == null) return fallback;
  final uri = Uri.tryParse(path);
  if (uri?.scheme == 'subsonic') {
    final bytes = ref.watch(remoteArtworkProvider(path)).value;
    return bytes == null ? fallback : MemoryImage(bytes);
  }
  if (!kIsWeb && uri != null && SpotifyArtworkCache.handles(uri)) {
    final bytes = ref.watch(spotifyArtworkProvider(path)).value;
    return bytes == null ? fallback : MemoryImage(bytes);
  }
  if (uri?.scheme == 'http' || uri?.scheme == 'https') {
    return NetworkImage(path);
  }
  return fileArtwork(path);
}
