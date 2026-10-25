import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/theme/ipod_gradients.dart';
import 'package:classipod/core/theme/ipod_typography.dart';
import 'package:classipod/core/widgets/selected_marquee_text.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

class DisplayListTile extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback? onTap;

  /// Marks the active choice of a set, like a classic iPod setting; the row
  /// then shows a checkmark instead of the chevron.
  final bool isChecked;

  const DisplayListTile({
    super.key,
    required this.text,
    required this.isSelected,
    this.onTap,
    this.isChecked = false,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = IpodTypography.menu.copyWith(
      color: isSelected
          ? context.appInverseTextColor
          : context.appPrimaryTextColor,
    );

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 30,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isSelected
                ? const Border(
                    top: BorderSide(
                      color: AppPalette.selectedTileTopBorderColor,
                    ),
                    bottom: BorderSide(
                      color: AppPalette.selectedTileBottomBorderColor,
                    ),
                  )
                : null,
            gradient: isSelected ? IpodGradients.selectionFor(context) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: SelectedMarqueeText(
                    text,
                    isSelected: isSelected,
                    style: textStyle,
                  ),
                ),
                if (isChecked)
                  Icon(
                    CupertinoIcons.checkmark_alt,
                    color: isSelected
                        ? context.appInverseTextColor
                        : context.appPrimaryTextColor,
                  )
                else if (isSelected)
                  Icon(
                    CupertinoIcons.right_chevron,
                    color: context.appInverseTextColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
