import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/theme/ipod_typography.dart';
import 'package:classipod/core/widgets/marquee_text.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_artwork_scene.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Song title, artist and album beside or under the cover, with the rating
/// and the shuffle and repeat states.
class NowPlayingMetadata extends ConsumerWidget {
  /// Title and one artist · album line, for short displays.
  final bool compact;

  const NowPlayingMetadata({super.key, this.compact = false});

  /// White at these opacities keeps 4.5:1 over every artwork backdrop.
  static const secondaryAlpha = 0.76;
  static const tertiaryAlpha = 0.66;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(nowPlayingDetailsProvider);
    final metadata = details.currentMetadata;
    final rating = metadata?.rating ?? 0;
    final artist =
        metadata?.trackArtistNames?.join(', ') ??
        context.localization.unknownArtist;
    final album = metadata?.albumName ?? context.localization.unknownAlbum;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarqueeText(
          metadata?.trackName ?? context.localization.unknownSong,
          key: ValueKey('title-${metadata?.identity}'),
          style: IpodTypography.title.copyWith(
            color: CupertinoColors.white,
            fontSize: compact ? 17 : 19,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                compact ? '$artist · $album' : artist,
                key: const ValueKey('now-playing-artist-line'),
                style: IpodTypography.metadata.copyWith(
                  color: CupertinoColors.white.withValues(
                    alpha: secondaryAlpha,
                  ),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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
        if (!compact) ...[
          const SizedBox(height: 2),
          Text(
            album,
            key: const ValueKey('now-playing-album-line'),
            style: IpodTypography.metadata.copyWith(
              color: CupertinoColors.white.withValues(alpha: tertiaryAlpha),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// Everything under the title: live lyrics on a translucent surface tinted
/// from the cover, the progress bar and Go to Artist. Lyrics take whatever
/// height is left and disappear first when the window is short, so the
/// controls are never clipped.
class NowPlayingPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = ArtworkAccent.maybeOf(context);
    final accent = palette?.accent;
    final muted = CupertinoColors.white.withValues(
      alpha: NowPlayingMetadata.tertiaryAlpha,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxHeight < minLyricsHeight) {
                return const SizedBox.shrink();
              }
              // A thin translucent fill, not a blur: the backdrop behind it
              // is a smooth gradient, so blurring would cost GPU time on
              // every scroll frame for no visible difference.
              return DecoratedBox(
                key: const ValueKey('now-playing-lyrics-surface'),
                decoration: BoxDecoration(
                  color: palette?.glass ?? const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                  : muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _EdgeFade(
                            child:
                                lyrics ??
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    lyricsMessage,
                                    style: IpodTypography.metadata.copyWith(
                                      color: muted,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        bottomBar,
        if (onGoToArtist != null)
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
    );
  }
}

/// Lines scrolling out of the lyrics surface fade instead of being cut
/// through. The mask is redrawn only when the lyrics repaint.
class _EdgeFade extends StatelessWidget {
  final Widget child;

  const _EdgeFade({required this.child});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final top = 8 / bounds.height;
        final bottom = 1 - 28 / bounds.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, top.clamp(0, 0.5), bottom.clamp(0.5, 1), 1],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
