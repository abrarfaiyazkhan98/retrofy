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

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.scrollController,
  });

  @override
  ConsumerState<SyncedLyricsView> createState() => SyncedLyricsViewState();
}

class SyncedLyricsViewState extends ConsumerState<SyncedLyricsView> {
  /// Lines are emphasised slightly early so the eye arrives with the voice.
  static const _lead = Duration(milliseconds: 150);
  static const _manualPause = Duration(seconds: 4);

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
        ArtworkAccent.maybeOf(context)?.accent ?? CupertinoColors.white;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    const base = TextStyle(
      fontSize: 17,
      height: 1.35,
      fontWeight: FontWeight.w700,
    );
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

    return CupertinoScrollbar(
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
                Padding(
                  key: _lineKeys[i],
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: AnimatedDefaultTextStyle(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    style: base.copyWith(
                      color: i == _current
                          ? accent
                          : CupertinoColors.white.withValues(
                              alpha: i < _current ? 0.42 : 0.62,
                            ),
                    ),
                    // Instrumental gaps are blank lines in LRC.
                    child: Text(
                      lyrics.lines[i].text.isEmpty ? '♪' : lyrics.lines[i].text,
                    ),
                  ),
                ),
            attribution,
          ],
        ),
      ),
    );
  }
}
