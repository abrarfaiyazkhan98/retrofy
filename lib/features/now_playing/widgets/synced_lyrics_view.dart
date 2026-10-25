import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/lyrics/lyrics.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/services/playback/playback_backend.dart';
import 'package:classipod/core/spotify/spotify_playback_controller.dart';
import 'package:classipod/features/now_playing/widgets/now_playing_artwork_scene.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lyrics over the dimmed artwork. Synced lyrics follow playback, keeping
/// the sung line emphasised and in view; plain lyrics simply scroll.
class SyncedLyricsView extends ConsumerStatefulWidget {
  final Lyrics lyrics;
  final ScrollController scrollController;
  final double fontSize;
  final FontWeight fontWeight;

  /// Line height as a multiple of [fontSize].
  final double lineHeight;

  /// Colour of the sung line; the artwork accent when null.
  final Color? currentColor;

  /// Seeks to a tapped synced line; lines are not tappable when null.
  final ValueChanged<Duration>? onLineTap;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.scrollController,
    this.fontSize = 17,
    this.fontWeight = FontWeight.w700,
    this.lineHeight = 1.3,
    this.currentColor,
    this.onLineTap,
  });

  @override
  ConsumerState<SyncedLyricsView> createState() => SyncedLyricsViewState();
}

class SyncedLyricsViewState extends ConsumerState<SyncedLyricsView> {
  /// Lines are emphasised slightly early so the eye arrives with the voice.
  static const _lead = Duration(milliseconds: 150);
  static const _manualPause = Duration(seconds: 4);

  /// White at these opacities marks sung and upcoming lines; upcoming
  /// lines keep 4.5:1 over every artwork backdrop.
  static const sungAlpha = 0.48;
  static const upcomingAlpha = 0.7;

  StreamSubscription<PlaybackState>? _positions;
  late List<GlobalKey> _lineKeys;
  int _current = -1;
  DateTime? _followAfter;

  @override
  void initState() {
    super.initState();
    _lineKeys = _keysFor(widget.lyrics);
  }

  @override
  void didUpdateWidget(SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _lineKeys = _keysFor(widget.lyrics);
      _current = -1;
    }
  }

  List<GlobalKey> _keysFor(Lyrics lyrics) =>
      List.generate(lyrics.lines.length, (_) => GlobalKey());

  /// Called when the wheel scrolls the lyrics, so following waits a moment.
  void pauseFollowing() => _followAfter = DateTime.now().add(_manualPause);

  /// Returns to the line being sung at once, after manual scrolling.
  void resumeFollowing() {
    _followAfter = null;
    _current = -2;
    _onPosition();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_positions == null && widget.lyrics.isSynced) _listen();
  }

  void _listen() {
    // The same position source as the progress bar, for whichever engine
    // owns Now Playing; no extra timers.
    final spotify =
        ref.read(playbackBackendProvider) == PlaybackBackend.spotify;
    final stream = spotify
        ? ref.read(spotifyPlaybackControllerProvider.notifier).playbackStates
        : ref.read(libraryAudioHandlerProvider).playbackState;
    _positions = stream.listen((_) => _onPosition());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPosition());
  }

  void _onPosition() {
    if (!mounted || !widget.lyrics.isSynced) return;
    final position = ref
        .read(audioPlayerServiceProvider.notifier)
        .displayPosition;
    final index = widget.lyrics.indexAt(position + _lead);
    if (index == _current) return;
    // Pausing stops position updates, so the highlight holds; a seek or a
    // skip moves it on the next update.
    setState(() => _current = index);
    final follow = _followAfter;
    if (follow != null && DateTime.now().isBefore(follow)) return;
    final target = _lineKeys[index < 0 ? 0 : index].currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        alignment: 0.35,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_positions?.cancel());
    super.dispose();
  }

  String _attribution(BuildContext context) {
    final l10n = context.localization;
    return switch (widget.lyrics.source) {
      LyricsSource.lrclib => l10n.lyricsFromLrclib,
      LyricsSource.embedded => l10n.lyricsFromTags,
      LyricsSource.lrcFile => l10n.lyricsFromLrcFile,
    };
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final accent =
        widget.currentColor ??
        ArtworkAccent.maybeOf(context)?.accent ??
        CupertinoColors.white;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final base = TextStyle(
      fontSize: widget.fontSize,
      height: widget.lineHeight,
      fontWeight: widget.fontWeight,
    );
    final onLineTap = widget.onLineTap;
    final gap = widget.fontSize * 0.18;
    final attribution = Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 40),
      child: Text(
        _attribution(context),
        style: TextStyle(
          fontSize: 11,
          color: CupertinoColors.white.withValues(alpha: 0.6),
        ),
      ),
    );

    return NotificationListener<UserScrollNotification>(
      // Dragging the lyrics by touch pauses following, like the wheel.
      onNotification: (_) {
        pauseFollowing();
        return false;
      },
      child: CupertinoScrollbar(
        controller: widget.scrollController,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: const EdgeInsets.only(right: 10, top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!lyrics.isSynced)
                Text(lyrics.plain ?? '', style: base)
              else
                for (var i = 0; i < lyrics.lines.length; i++)
                  GestureDetector(
                    key: _lineKeys[i],
                    behavior: HitTestBehavior.opaque,
                    onTap: onLineTap == null
                        ? null
                        : () => onLineTap(lyrics.lines[i].time),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: gap),
                      child: AnimatedDefaultTextStyle(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        style: base.copyWith(
                          color: i == _current
                              ? accent
                              : CupertinoColors.white.withValues(
                                  alpha: i < _current
                                      ? sungAlpha
                                      : upcomingAlpha,
                                ),
                        ),
                        // Instrumental gaps are blank lines in LRC.
                        child: Text(
                          lyrics.lines[i].text.isEmpty
                              ? '♪'
                              : lyrics.lines[i].text,
                        ),
                      ),
                    ),
                  ),
              attribution,
            ],
          ),
        ),
      ),
    );
  }
}
