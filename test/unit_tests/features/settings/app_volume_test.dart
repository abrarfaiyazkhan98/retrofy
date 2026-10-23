// ignore_for_file: depend_on_referenced_packages
import 'package:classipod/core/providers/shared_preferences_with_cache_provider.dart';
import 'package:classipod/core/services/audio_player_service.dart';
import 'package:classipod/core/services/playback/playback_backend.dart';
import 'package:classipod/features/settings/controller/settings_preferences_controller.dart';
import 'package:classipod/features/settings/models/volume_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class VolumePlayer extends Fake implements AudioPlayer {
  @override
  double volume = 0.5;

  @override
  Future<void> setVolume(double value) async => volume = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('app_volume', () {
    test(
      'wheel volume works while Now Playing watches the volume mode',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final player = VolumePlayer();
        final container = ProviderContainer(
          overrides: [audioPlayerProvider.overrideWithValue(player)],
        );
        addTearDown(container.dispose);
        await container.read(sharedPreferencesWithCacheProvider.future);
        final settings = container.read(
          settingsPreferencesControllerProvider.notifier,
        );
        if (container.read(settingsPreferencesControllerProvider).volumeMode !=
            VolumeMode.app) {
          await settings.toggleVolumeMode();
        }
        // The Now Playing volume bar keeps this provider alive; reading it
        // back from the settings controller used to be a provider cycle.
        final sub = container.listen(appVolumeActiveProvider, (_, _) {});
        addTearDown(sub.close);
        expect(container.read(appVolumeActiveProvider), isTrue);

        await settings.increaseVolume();
        expect(player.volume, closeTo(0.55, 1e-9));
        await settings.decreaseVolume();
        expect(player.volume, closeTo(0.5, 1e-9));

        container.read(playbackBackendProvider.notifier).backend =
            PlaybackBackend.spotify;
        expect(container.read(appVolumeActiveProvider), isFalse);
      },
    );
  });
}
