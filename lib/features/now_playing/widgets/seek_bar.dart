import 'package:classipod/core/constants/app_palette.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/theme/ipod_gradients.dart';
import 'package:classipod/core/widgets/subtle_reflection.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_artwork_scene.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SeekBar extends ConsumerWidget {
  final double max;
  final double value;

  const SeekBar({super.key, required this.max, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkTheme =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final gradient = isDarkTheme
        ? IpodGradients.darkSliderTrack
        : IpodGradients.sliderTrack;
    final borderColor = isDarkTheme
        ? AppPalette.darkSliderBorderColor
        : AppPalette.sliderBorderColor;

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GestureDetector(
                  onTapDown: (tapDownDetails) async {
                    final targetSeekValue =
                        (tapDownDetails.localPosition.dx * max) /
                        constraints.maxWidth;
                    await ref
                        .read(audioPlayerServiceProvider.notifier)
                        .seekToDuration(targetSeekValue.floor());
                  },
                  child: SizedBox(
                    height: 20,
                    width: constraints.maxWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: gradient,
                        border: Border.all(color: borderColor),
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: AnimatedContainer(
                  height: 20,
                  width: (value / max) * constraints.maxWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  duration: const Duration(milliseconds: 10),
                  child: SubtleReflection(
                    height: 20,
                    child: SizedBox(
                      width: double.infinity,
                      height: 20,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: _progress(context)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The cover's accent on Now Playing; the classic blue elsewhere.
LinearGradient _progress(BuildContext context) {
  final palette = ArtworkAccent.maybeOf(context);
  return palette == null
      ? IpodGradients.progress
      : ArtworkAccent.progressOf(palette);
}
