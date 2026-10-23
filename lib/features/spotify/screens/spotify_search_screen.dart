import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/extensions/go_router_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/spotify/spotify_api_client.dart';
import 'package:classipod/core/widgets/artwork_list_tile.dart';
import 'package:classipod/core/widgets/input_text_bar.dart';
import 'package:classipod/features/custom_screen_elements/custom_input_text_screen.dart';
import 'package:classipod/features/spotify/providers/spotify_library_providers.dart';
import 'package:classipod/features/spotify/screens/spotify_browse_screen.dart';
import 'package:classipod/features/spotify/widgets/spotify_status_view.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _ResultRow {
  final String title;
  final String? subtitle;
  final String? artworkPath;
  final IconData? icon;
  final Future<void> Function() open;

  const _ResultRow({
    required this.title,
    required this.open,
    this.subtitle,
    this.artworkPath,
    this.icon,
  });
}

class SpotifySearchScreen extends ConsumerStatefulWidget {
  const SpotifySearchScreen({super.key});

  @override
  ConsumerState createState() => _SpotifySearchScreenState();
}

class _SpotifySearchScreenState extends ConsumerState<SpotifySearchScreen>
    with CustomInputTextScreen {
  /// Searches are sent once typing pauses, not on every wheel click.
  String _query = '';
  Timer? _debounce;

  @override
  String get routeName => Routes.spotifySearch.name;

  @override
  int get extraDisplayItems => 1;

  AsyncValue<SpotifySearchResults> get _results =>
      ref.watch(spotifySearchProvider(_query));

  @override
  List<_ResultRow> get displayItems {
    final results = _results.value;
    if (results == null) return const [];
    return [
      for (final artist in results.artists)
        _ResultRow(
          title: artist.name,
          subtitle: context.localization.artistsScreenTitle,
          artworkPath: artist.imageUrl,
          icon: artist.imageUrl == null ? CupertinoIcons.person_alt : null,
          open: () => openSpotifyArtist(context, artist),
        ),
      for (final album in results.albums)
        _ResultRow(
          title: album.name,
          subtitle: album.artistLine,
          artworkPath: album.imageUrl,
          open: () => openSpotifyAlbum(context, album),
        ),
      for (var i = 0; i < results.tracks.length; i++)
        _ResultRow(
          title: results.tracks[i].getTrackName,
          subtitle: results.tracks[i].getTrackArtistNames,
          artworkPath: results.tracks[i].thumbnailPath,
          open: () => _playTrack(results, i),
        ),
    ];
  }

  Future<void> _playTrack(SpotifySearchResults results, int index) async {
    try {
      await ref
          .read(audioPlayerServiceProvider.notifier)
          .playSpotify(tracks: results.tracks, index: index);
    } catch (error) {
      if (mounted) setState(() => _playbackError = error);
      return;
    }
    if (mounted) await context.openUniqueNamed(Routes.nowPlaying.name);
  }

  Object? _playbackError;

  void _onTextChanged(String value) {
    setState(() {
      inputText = value;
      _playbackError = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Future<void> onSelectAction() => _select(selectedDisplayItem);

  Future<void> _select(int index) async {
    setState(() => selectedDisplayItem = index);
    if (index == 0) {
      setState(() => isInputTextBarActive = !isInputTextBarActive);
      return;
    }
    final rows = displayItems;
    if (index - 1 < rows.length) await rows[index - 1].open();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final rows = displayItems;
    final l10n = context.localization;
    final String summary;
    if (_playbackError != null) {
      summary = spotifyErrorText(context, _playbackError);
    } else if (results.hasError) {
      summary = spotifyErrorText(context, results.error);
    } else if (_query.trim().isEmpty || rows.isEmpty) {
      summary = l10n.searchEmptyText;
    } else {
      summary = '${l10n.resultsForText} $_query';
    }
    return CupertinoPageScaffold(
      resizeToAvoidBottomInset: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Flexible(
                child: CupertinoScrollbar(
                  controller: scrollController,
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: rows.length + 1,
                    itemExtent: ArtworkListTile.height,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ArtworkListTile(
                          title: l10n.searchScreenTitle,
                          subtitle: summary,
                          icon: results.isLoading
                              ? CupertinoIcons.hourglass
                              : CupertinoIcons.search,
                          isSelected: selectedDisplayItem == 0,
                          onTap: () => unawaited(_select(0)),
                        );
                      }
                      final row = rows[index - 1];
                      return ArtworkListTile(
                        title: row.title,
                        subtitle: row.subtitle,
                        artworkPath: row.artworkPath,
                        icon: row.icon,
                        isSelected: selectedDisplayItem == index,
                        onTap: () => unawaited(_select(index)),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (isInputTextBarActive)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: InputTextBar(
                inputTextBarController: inputTextBarController,
                onSearchTextChanged: _onTextChanged,
              ),
            ),
        ],
      ),
    );
  }
}
