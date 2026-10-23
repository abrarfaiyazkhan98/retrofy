import 'package:classipod/core/models/shared_preference_keys.dart';
import 'package:classipod/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which library the Music menu lists. Switching only changes what is
/// browsed; whatever is playing keeps playing.
enum MusicSource { library, spotify }

final musicSourceProvider = NotifierProvider<MusicSourceNotifier, MusicSource>(
  MusicSourceNotifier.new,
);

/// Remembers the last chosen source across launches.
class MusicSourceNotifier extends Notifier<MusicSource> {
  @override
  MusicSource build() {
    final saved = ref
        .read(sharedPreferencesWithCacheProvider)
        .value
        ?.getString(SharedPreferencesKeys.musicSource.name);
    return MusicSource.values.firstWhere(
      (source) => source.name == saved,
      orElse: () => MusicSource.library,
    );
  }

  Future<void> choose(MusicSource source) async {
    state = source;
    await ref
        .read(sharedPreferencesWithCacheProvider)
        .value
        ?.setString(SharedPreferencesKeys.musicSource.name, source.name);
  }
}
