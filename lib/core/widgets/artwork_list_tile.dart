import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/theme/ipod_gradients.dart';
import 'package:classipod/core/theme/ipod_typography.dart';
import 'package:classipod/core/widgets/artwork_image.dart';
import 'package:classipod/core/widgets/selected_marquee_text.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Two-line list row with artwork, matching the search result rows. Shows
/// [icon] on the classic grey tile when there is no artwork to show.
class ArtworkListTile extends ConsumerWidget {
  static const double height = 54;

  final String title;
  final String? subtitle;
  final String? artworkPath;
  final IconData? icon;
  final bool isSelected;
  final bool isCurrentlyPlaying;
  final VoidCallback onTap;

  const ArtworkListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.artworkPath,
    this.icon,
    required this.isSelected,
    this.isCurrentlyPlaying = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final borderColor = isDarkTheme
        ? AppPalette.darkListTileBorderColor
        : AppPalette.lightListTileBorderColor;
    final textColor = isSelected
        ? context.appInverseTextColor
        : context.appPrimaryTextColor;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isSelected ? IpodGradients.selectionFor(context) : null,
            border: isSelected
                ? null
                : Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              if (icon != null)
                SizedBox(
                  height: height,
                  width: height,
                  child: ColoredBox(
                    color: AppPalette.defaultIconBackgroundColor,
                    child: Center(
                      child: Icon(
                        icon,
                        size: 40,
                        color: AppPalette.statusBarGradientColor2,
                      ),
                    ),
                  ),
                )
              else
                Image(
                  image: artworkImage(
                    ref,
                    artworkPath,
                    decodeSize:
                        (height * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                  ),
                  errorBuilder: (_, _, _) => Image.asset(
                    Assets.defaultAlbumCoverImage,
                    fit: BoxFit.cover,
                    height: height,
                    width: height,
                  ),
                  height: height,
                  width: height,
                  fit: BoxFit.cover,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectedMarqueeText(
                      title,
                      isSelected: isSelected,
                      style: IpodTypography.title.copyWith(color: textColor),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: IpodTypography.metadata.copyWith(
                          color: isSelected
                              ? context.appInverseTextColor
                              : context.appSecondaryTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (isCurrentlyPlaying || isSelected)
                Icon(
                  isCurrentlyPlaying
                      ? CupertinoIcons.volume_up
                      : CupertinoIcons.right_chevron,
                  color: textColor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
