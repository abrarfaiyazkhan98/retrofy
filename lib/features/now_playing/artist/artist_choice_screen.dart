import 'dart:async';

import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:classipod/core/navigation/routes.dart';
import 'package:classipod/core/widgets/display_list_tile.dart';
import 'package:classipod/features/custom_screen_elements/custom_screen.dart';
import 'package:classipod/features/now_playing/artist/go_to_artist.dart';
import 'package:classipod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the playing track's artist on Spotify. One artist opens at once; a
/// track with several artists shows [ArtistChoiceScreen] to pick one.
/// Library and Subsonic tracks browse the artist in the local library.
Future<void> goToArtist(BuildContext context, WidgetRef ref) async {
  final track = ref.read(nowPlayingDetailsProvider).currentMetadata;
  if (track == null) return;
  if (!track.isSpotify) {
    final artistName = track.getMainArtistName;
    context.goNamed(
      Routes.artistAlbums.name,
      pathParameters: {'artistName': artistName},
      queryParameters: {'selectedArtist': artistName},
    );
    return;
  }
  final List<ArtistLink> links;
  try {
    links = await ref.read(currentArtistLinksProvider.future);
  } catch (_) {
    if (context.mounted) _showUnavailable(context);
    return;
  }
  if (!context.mounted) return;
  if (links.isEmpty) {
    _showUnavailable(context);
  } else if (links.length == 1) {
    if (!await openArtistLink(links.single, ref.read(urlOpenerProvider)) &&
        context.mounted) {
      _showUnavailable(context);
    }
  } else {
    await context.pushNamed(Routes.artistChoice.name, extra: links);
  }
}

void _showUnavailable(BuildContext context) {
  unawaited(
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => CupertinoAlertDialog(
        content: Text(context.localization.artistUnavailable),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.localization.okButtonText),
          ),
        ],
      ),
    ),
  );
}

class ArtistChoiceScreen extends ConsumerStatefulWidget {
  final List<ArtistLink> artists;

  const ArtistChoiceScreen({super.key, required this.artists});

  @override
  ConsumerState createState() => _ArtistChoiceScreenState();
}

class _ArtistChoiceScreenState extends ConsumerState<ArtistChoiceScreen>
    with CustomScreen {
  @override
  String get routeName => Routes.artistChoice.name;

  @override
  List<ArtistLink> get displayItems => widget.artists;

  @override
  Future<void> onSelectPressed() => _open(selectedDisplayItem);

  Future<void> _open(int index) async {
    setState(() => selectedDisplayItem = index);
    final opened = await openArtistLink(
      displayItems[index],
      ref.read(urlOpenerProvider),
    );
    if (!opened && mounted) _showUnavailable(context);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: ListView.builder(
        controller: scrollController,
        itemCount: displayItems.length,
        itemBuilder: (context, index) => DisplayListTile(
          text: displayItems[index].name,
          isSelected: index == selectedDisplayItem,
          onTap: () => unawaited(_open(index)),
        ),
      ),
    );
  }
}
