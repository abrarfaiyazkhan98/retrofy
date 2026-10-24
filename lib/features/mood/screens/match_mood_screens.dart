import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/extensions/go_router_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/theme/ipod_typography.dart';
import 'package:classipod/core/widgets/album_art_song_list_tile.dart';
import 'package:classipod/core/widgets/artwork_list_tile.dart';
import 'package:classipod/core/widgets/display_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/mood/engine/mood_engine.dart';
import 'package:classipod/features/mood/models/mood_selection.dart';
import 'package:classipod/features/spotify/widgets/spotify_status_view.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _MatchMode { mood, tempo }

/// Match Your Mood: two rows, Mood and Tempo, for the click wheel.
class MatchMoodScreen extends ConsumerStatefulWidget {
  const MatchMoodScreen({super.key});

  @override
  ConsumerState createState() => _MatchMoodScreenState();
}

class _MatchMoodScreenState extends ConsumerState<MatchMoodScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.matchMood.name;

  @override
  List<_MatchMode> get displayItems => _MatchMode.values;

  @override
  Future<void> onSelectPressed() => _open(displayItems[selectedDisplayItem]);

  Future<void> _open(_MatchMode mode) async {
    setState(() => selectedDisplayItem = mode.index);
    await context.pushNamed(
      mode == _MatchMode.mood ? Routes.moodList.name : Routes.tempoList.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: ListView(
        controller: scrollController,
        children: [
          for (final mode in _MatchMode.values)
            DisplayListTile(
              text: mode == _MatchMode.mood
                  ? context.localization.moodTitle
                  : context.localization.tempoTitle,
              isSelected: selectedDisplayItem == mode.index,
              onTap: () => unawaited(_open(mode)),
            ),
        ],
      ),
    );
  }
}

/// The eight moods, each with one plain icon.
class MoodListScreen extends ConsumerStatefulWidget {
  const MoodListScreen({super.key});

  @override
  ConsumerState createState() => _MoodListScreenState();
}

class _MoodListScreenState extends ConsumerState<MoodListScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.moodList.name;

  @override
  double get displayTileHeight => ArtworkListTile.height;

  @override
  List<Mood> get displayItems => Mood.values;

  @override
  Future<void> onSelectPressed() => _open(displayItems[selectedDisplayItem]);

  Future<void> _open(Mood mood) async {
    setState(() => selectedDisplayItem = mood.index);
    await context.pushNamed(Routes.moodPreview.name, extra: MoodChoice(mood));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: ListView.builder(
        controller: scrollController,
        itemCount: displayItems.length,
        itemExtent: ArtworkListTile.height,
        itemBuilder: (context, index) {
          final mood = displayItems[index];
          return ArtworkListTile(
            title: mood.title(context),
            icon: mood.icon,
            isSelected: selectedDisplayItem == index,
            onTap: () => unawaited(_open(mood)),
          );
        },
      ),
    );
  }
}

/// Tempo presets and a custom BPM row.
class TempoListScreen extends ConsumerStatefulWidget {
  const TempoListScreen({super.key});

  @override
  ConsumerState createState() => _TempoListScreenState();
}

class _TempoListScreenState extends ConsumerState<TempoListScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.tempoList.name;

  @override
  double get displayTileHeight => ArtworkListTile.height;

  /// [TempoPreset]s, then null for Custom BPM.
  @override
  List<TempoPreset?> get displayItems => [...TempoPreset.values, null];

  @override
  Future<void> onSelectPressed() => _open(selectedDisplayItem);

  Future<void> _open(int index) async {
    setState(() => selectedDisplayItem = index);
    final preset = displayItems[index];
    if (preset == null) {
      await context.pushNamed(Routes.customBpm.name);
    } else {
      await context.pushNamed(
        Routes.moodPreview.name,
        extra: TempoChoice.preset(preset),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = displayItems;
    return CupertinoPageScaffold(
      child: ListView.builder(
        controller: scrollController,
        itemCount: items.length,
        itemExtent: ArtworkListTile.height,
        itemBuilder: (context, index) {
          final preset = items[index];
          return ArtworkListTile(
            title:
                preset?.title(context) ?? context.localization.customBpmTitle,
            subtitle: preset?.rangeLabel,
            icon: CupertinoIcons.metronome,
            isSelected: selectedDisplayItem == index,
            onTap: () => unawaited(_open(index)),
          );
        },
      ),
    );
  }
}

/// The BPM slider: the wheel sets a target from 60 to 200 BPM.
class CustomBpmScreen extends ConsumerStatefulWidget {
  const CustomBpmScreen({super.key});

  @override
  ConsumerState createState() => _CustomBpmScreenState();
}

class _CustomBpmScreenState extends ConsumerState<CustomBpmScreen>
    with CustomScreen {
  static const _min = 60, _max = 200;
  int _bpm = 120;

  @override
  String get routeName => Routes.customBpm.name;

  @override
  List<Object> get displayItems => const [];

  void _set(int bpm) => setState(() => _bpm = bpm.clamp(_min, _max));

  @override
  void scrollForward() => _set(_bpm + 1);

  @override
  void scrollBackward() => _set(_bpm - 1);

  @override
  Future<void> onSelectPressed() => context.pushNamed(
    Routes.moodPreview.name,
    extra: TempoChoice.around(_bpm),
  );

  @override
  Widget build(BuildContext context) {
    final primary = context.appPrimaryTextColor;
    return CupertinoPageScaffold(
      child: GestureDetector(
        onTap: () => unawaited(onSelectPressed()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_bpm',
                key: const ValueKey('custom-bpm'),
                style: IpodTypography.title.copyWith(
                  fontSize: 44,
                  color: primary,
                ),
              ),
              Text('BPM', style: TextStyle(color: primary)),
              const SizedBox(height: 12),
              CupertinoSlider(
                value: _bpm.toDouble(),
                min: _min.toDouble(),
                max: _max.toDouble(),
                divisions: _max - _min,
                onChanged: (value) => _set(value.round()),
              ),
              const SizedBox(height: 12),
              Text(
                context.localization.customBpmHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PreviewRow { start, basis }

/// The session Match Your Mood built: Start, how the tracks were chosen,
/// and the first few tracks.
class MoodPreviewScreen extends ConsumerStatefulWidget {
  final MoodSelection selection;

  const MoodPreviewScreen({super.key, required this.selection});

  @override
  ConsumerState createState() => _MoodPreviewScreenState();
}

class _MoodPreviewScreenState extends ConsumerState<MoodPreviewScreen>
    with CustomScreen {
  Object? _error;
  bool _starting = false;

  @override
  String get routeName => Routes.moodPreview.name;

  @override
  double get displayTileHeight => ArtworkListTile.height;

  MoodSession? get _session =>
      ref.watch(moodSessionProvider(widget.selection)).value;

  /// Only Start is selectable; the explanation and tracks are information.
  @override
  List<Object> get displayItems => [
    if (_session?.canStart ?? false) _PreviewRow.start,
  ];

  @override
  Future<void> onSelectPressed() => _start();

  Future<void> _start() async {
    final session = _session;
    if (session == null || !session.canStart || _starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await ref.read(moodSessionStarterProvider)(session);
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = error;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _starting = false);
    await context.openUniqueNamed(Routes.nowPlaying.name);
  }

  String _basisText(MoodSession session) {
    final l10n = context.localization;
    return switch (session.basis) {
      MatchBasis.audioFeatures => l10n.moodBasisAudioFeatures,
      MatchBasis.playlistName => l10n.moodBasisPlaylist(
        session.sourceName ?? '',
      ),
      MatchBasis.genre => l10n.moodBasisGenre,
      MatchBasis.fallbackLikedSongs => l10n.moodBasisFallbackLiked,
      MatchBasis.fallbackLibrary => l10n.moodBasisFallbackLibrary,
      MatchBasis.noTempoData => l10n.moodBasisNoTempo,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(moodSessionProvider(widget.selection));
    final session = state.value;
    if (session == null) {
      if (state.hasError) return SpotifyStatusView.error(state.error);
      return SpotifyStatusView.message(context.localization.moodFinding);
    }
    final l10n = context.localization;
    final secondary = context.appPrimaryTextColor.withValues(alpha: 0.7);
    final startTitle = _starting
        ? l10n.spotifyConnecting
        : session.basis == MatchBasis.noTempoData
        ? l10n.moodShuffleLikedInstead
        : l10n.moodStart;
    final rows = <Widget>[
      if (session.canStart)
        ArtworkListTile(
          key: const ValueKey('mood-start'),
          title: startTitle,
          subtitle: _error == null ? null : spotifyErrorText(context, _error),
          icon: _error == null
              ? CupertinoIcons.play_arrow_solid
              : CupertinoIcons.exclamationmark_triangle,
          isSelected: selectedDisplayItem == 0,
          onTap: () => unawaited(_start()),
        ),
      Padding(
        key: const ValueKey(_PreviewRow.basis),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Text(
          session.canStart
              ? _basisText(session)
              : '${_basisText(session)} ${l10n.moodNothingToPlay}',
          style: TextStyle(fontSize: 13, color: secondary),
        ),
      ),
      if (session.contextUri != null &&
          session.tracks.isEmpty &&
          session.basis == MatchBasis.playlistName)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            l10n.moodPreviewUnavailable,
            style: TextStyle(fontSize: 13, color: secondary),
          ),
        ),
      // A tempo that cannot be matched previews nothing as a "match".
      if (session.basis != MatchBasis.noTempoData)
        for (final track in session.preview)
          AlbumArtSongListTile(
            songMetadata: track,
            isSelected: false,
            isCurrentlyPlaying: false,
            onTap: () => unawaited(_start()),
            onLongPress: () {},
          ),
    ];
    return CupertinoPageScaffold(
      child: ListView(controller: scrollController, children: rows),
    );
  }
}
