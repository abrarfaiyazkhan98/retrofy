import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/theme/ipod_typography.dart';
import 'package:classipod/core/widgets/marquee_text.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Track details laid over the full-screen artwork (see
/// `NowPlayingArtworkScene`), anchored to the bottom where the scrim is
/// darkest so the text stays readable on any cover.
class NowPlayingWidget extends ConsumerWidget {
  const NowPlayingWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowPlayingDetails = ref.watch(nowPlayingDetailsProvider);
    final metadata = nowPlayingDetails.currentMetadata;
    final secondary = IpodTypography.metadata.copyWith(
      color: CupertinoColors.white.withValues(alpha: 0.82),
    );
    final rating = metadata?.rating ?? 0;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey('Now Playing-${metadata?.identity}'),
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarqueeText(
            metadata?.trackName ?? context.localization.unknownSong,
            style: IpodTypography.title.copyWith(
              color: CupertinoColors.white,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metadata?.getTrackArtistNames ?? context.localization.unknownArtist,
            style: secondary.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  metadata?.albumName ?? context.localization.unknownAlbum,
                  style: secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "  ·  ${nowPlayingDetails.queuePosition + 1} "
                "${context.localization.commonOfText} "
                "${nowPlayingDetails.metadataList.length}",
                style: secondary,
              ),
              if (rating != 0) ...[
                const SizedBox(width: 8),
                for (var i = 0; i < rating; i++)
                  Icon(
                    CupertinoIcons.star_fill,
                    size: 12,
                    color: context.appRatingIconColor,
                  ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
