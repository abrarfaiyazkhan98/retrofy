import 'dart:async';

import 'package:classipod/core/constants/assets.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/widgets/artwork_image.dart';
import 'package:classipod/features/music/album/providers/album_details_provider.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:classipod/features/now_playing/widgets/immersive_ambient_view.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/settings/models/artwork_glow.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Retrofy's Ambient Mode. With Artwork Glow on it is the immersive player;
/// with it off, the low-power black screen. Neither is the phone's Always On
/// Display, and neither keeps a wake lock, so the screen still turns off on
/// the system timeout.
class AmbientNowPlayingScreen extends ConsumerWidget {
  const AmbientNowPlayingScreen({super.key});

  /// Shows the ambient screen over the whole app until tapped.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          transitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 400),
          pageBuilder: (_, _, _) => const AmbientNowPlayingScreen(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glow = ref.watch(
      settingsPreferencesControllerProvider.select((s) => s.artworkGlow),
    );
    return glow == ArtworkGlowStyle.off
        ? const _LowPowerAmbientView()
        : const ImmersiveAmbientView();
  }
}

/// Black screen, small cover, minimal text that moves now and then so no
/// pixel stays lit for long. Any tap returns.
class _LowPowerAmbientView extends ConsumerStatefulWidget {
  const _LowPowerAmbientView();

  @override
  ConsumerState<_LowPowerAmbientView> createState() =>
      _LowPowerAmbientViewState();
}

class _LowPowerAmbientViewState extends ConsumerState<_LowPowerAmbientView>
    with WidgetsBindingObserver {
  /// Positions the block cycles through so no pixel stays lit for long.
  static const _positions = [
    Alignment(-0.6, -0.5),
    Alignment(0.5, -0.2),
    Alignment(-0.3, 0.35),
    Alignment(0.4, 0.55),
    Alignment.center,
  ];

  Timer? _refresh;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefresh();
  }

  /// One low-frequency timer: progress text every 30 s, position every 60 s.
  void _startRefresh() {
    _refresh?.cancel();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _tick++);
      _startRefresh();
    } else {
      _refresh?.cancel();
      _refresh = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    super.dispose();
  }

  String _clock(Duration value) {
    final seconds = value.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(nowPlayingDetailsProvider);
    final track = details.currentMetadata;
    final artwork = ref.watch(songAlbumArtworkProvider(track));
    final position = ref
        .read(audioPlayerServiceProvider.notifier)
        .displayPosition;
    final total = Duration(milliseconds: track?.getTrackDuration ?? 0);
    const grey = Color(0xFF8A8A8A);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: SafeArea(
          child: Align(
            alignment: _positions[(_tick ~/ 2) % _positions.length],
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: 0.8,
                    child: Image(
                      image: artworkImage(
                        ref,
                        artwork,
                        decodeSize:
                            (96 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Image.asset(
                        Assets.defaultAlbumCoverImage,
                        width: 96,
                        height: 96,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track?.getTrackName ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFBDBDBD),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track?.getTrackArtistNames ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: grey, fontSize: 14),
                        ),
                        if (total > Duration.zero) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${_clock(position)} / ${_clock(total)}',
                            style: const TextStyle(
                              color: grey,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
