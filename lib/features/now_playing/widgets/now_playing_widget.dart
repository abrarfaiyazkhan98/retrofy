import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/theme/ipod_typography.dart';
import 'package:classipod/core/widgets/marquee_text.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_artwork_scene.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// The album-coloured panel under the cover: song title, artist and album,
/// live lyrics, the progress bar and Go to Artist. Lyrics take whatever
/// height is left and disappear first when the window is short, so the
/// title and the controls are never clipped.
class NowPlayingPanel extends ConsumerWidget {
  /// Progress, scrubber, volume, rating or shuffle bar (fixed height).
  final Widget bottomBar;

  /// The lyrics, or null to show [lyricsMessage] instead.
  final Widget? lyrics;
  final String lyricsMessage;

  /// Synced lyrics are labelled live; plain lyrics are not.
  final bool lyricsSynced;

  /// The wheel is scrolling the lyrics (select returns to the sung line).
  final bool lyricsActive;
  final VoidCallback? onLyricsLabelTap;
  final VoidCallback? onGoToArtist;

  const NowPlayingPanel({
    super.key,
    required this.bottomBar,
    required this.lyricsMessage,
    this.lyrics,
    this.lyricsSynced = false,
    this.lyricsActive = false,
    this.onLyricsLabelTap,
    this.onGoToArtist,
  });

  /// Below this the lyrics section is left out entirely.
  static const minLyricsHeight = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(nowPlayingDetailsProvider);
    final metadata = details.currentMetadata;
    final secondary = IpodTypography.metadata.copyWith(
      color: CupertinoColors.white.withValues(alpha: 0.74),
      fontSize: 14,
    );
    final rating = metadata?.rating ?? 0;
    final accent = ArtworkAccent.maybeOf(context)?.accent;
    final artistLine = [
      metadata?.trackArtistNames?.join(', ') ??
          context.localization.unknownArtist,
      metadata?.albumName ?? context.localization.unknownAlbum,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarqueeText(
            metadata?.trackName ?? context.localization.unknownSong,
            key: ValueKey('title-${metadata?.identity}'),
            style: IpodTypography.title.copyWith(
              color: CupertinoColors.white,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  artistLine,
                  key: const ValueKey('now-playing-artist-line'),
                  style: secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (rating != 0)
                for (var i = 0; i < rating; i++)
                  Icon(
                    CupertinoIcons.star_fill,
                    size: 11,
                    color: context.appRatingIconColor,
                  ),
              if (details.isShuffleEnabled)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.shuffle,
                    size: 15,
                    color: CupertinoColors.white,
                  ),
                ),
              if (details.loopMode != LoopMode.off)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    details.loopMode == LoopMode.all
                        ? CupertinoIcons.repeat
                        : CupertinoIcons.repeat_1,
                    size: 15,
                    color: CupertinoColors.white,
                  ),
                ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxHeight < minLyricsHeight) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      height: 1,
                      color: CupertinoColors.white.withValues(alpha: 0.16),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onLyricsLabelTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        lyricsSynced
                            ? context.localization.liveLyricsLabel
                            : context.localization.lyricsLabel,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                          color: lyricsActive && accent != null
                              ? accent
                              : CupertinoColors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    Expanded(
                      child:
                          lyrics ??
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              lyricsMessage,
                              style: secondary.copyWith(
                                color: CupertinoColors.white.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
          bottomBar,
          if (metadata != null && onGoToArtist != null)
            GestureDetector(
              key: const ValueKey('go-to-artist'),
              onTap: onGoToArtist,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 34,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.arrow_up_right_square,
                      size: 16,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.localization.goToArtist,
                      style: const TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}
