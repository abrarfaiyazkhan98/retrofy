import 'package:classipod/core/extensions/build_context_extensions.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

/// A listening mood. [keywords] match playlist names and [genres] match
/// library genre tags; [valence] and [energy] are targets used only when
/// real audio features are available for the tracks.
enum Mood {
  happy(
    CupertinoIcons.sun_max,
    valence: 0.8,
    energy: 0.7,
    keywords: ['happy', 'feel good', 'good vibes', 'sunshine', 'joy', 'summer'],
    genres: ['pop', 'funk', 'disco', 'reggae'],
  ),
  chill(
    CupertinoIcons.cloud,
    valence: 0.5,
    energy: 0.3,
    keywords: ['chill', 'relax', 'lofi', 'lo-fi', 'calm', 'mellow', 'sunday'],
    genres: ['lo-fi', 'lofi', 'ambient', 'chill', 'acoustic', 'jazz'],
  ),
  energetic(
    CupertinoIcons.bolt,
    valence: 0.6,
    energy: 0.85,
    keywords: ['energy', 'hype', 'party', 'dance', 'banger', 'pump'],
    genres: ['edm', 'dance', 'electronic', 'house', 'punk'],
  ),
  focus(
    CupertinoIcons.scope,
    valence: 0.4,
    energy: 0.35,
    keywords: ['focus', 'study', 'concentration', 'deep work', 'reading'],
    genres: ['classical', 'instrumental', 'piano', 'soundtrack', 'ambient'],
  ),
  sad(
    CupertinoIcons.cloud_rain,
    valence: 0.2,
    energy: 0.35,
    keywords: ['sad', 'heartbreak', 'cry', 'melancholy', 'rainy', 'blue'],
    genres: ['blues', 'emo', 'ballad', 'sadcore'],
  ),
  romantic(
    CupertinoIcons.heart,
    valence: 0.55,
    energy: 0.45,
    keywords: ['love', 'romance', 'romantic', 'date night', 'slow jams'],
    genres: ['r&b', 'rnb', 'soul', 'love'],
  ),
  workout(
    CupertinoIcons.flame,
    valence: 0.6,
    energy: 0.9,
    keywords: ['workout', 'gym', 'running', 'run', 'training', 'cardio'],
    genres: ['hip hop', 'hip-hop', 'rap', 'metal', 'drum and bass'],
  ),
  nightDrive(
    CupertinoIcons.moon_stars,
    valence: 0.35,
    energy: 0.6,
    keywords: ['night', 'drive', 'driving', 'midnight', 'road trip', 'late'],
    genres: ['synthwave', 'darkwave', 'retrowave', 'trip hop'],
  );

  final IconData icon;
  final double valence;
  final double energy;
  final List<String> keywords;
  final List<String> genres;

  const Mood(
    this.icon, {
    required this.valence,
    required this.energy,
    required this.keywords,
    required this.genres,
  });

  String title(BuildContext context) {
    final l10n = context.localization;
    return switch (this) {
      happy => l10n.moodHappy,
      chill => l10n.moodChill,
      energetic => l10n.moodEnergetic,
      focus => l10n.moodFocus,
      sad => l10n.moodSad,
      romantic => l10n.moodRomantic,
      workout => l10n.moodWorkout,
      nightDrive => l10n.moodNightDrive,
    };
  }
}

/// BPM presets for Tempo. These are UI ranges, not definitions of a mood.
enum TempoPreset {
  slow(60, 85),
  relaxed(85, 105),
  moderate(105, 120),
  upbeat(120, 140),
  highEnergy(140, 170),
  intense(170, 220);

  final int minBpm;
  final int maxBpm;

  const TempoPreset(this.minBpm, this.maxBpm);

  String title(BuildContext context) {
    final l10n = context.localization;
    return switch (this) {
      slow => l10n.tempoSlow,
      relaxed => l10n.tempoRelaxed,
      moderate => l10n.tempoModerate,
      upbeat => l10n.tempoUpbeat,
      highEnergy => l10n.tempoHighEnergy,
      intense => l10n.tempoIntense,
    };
  }

  /// "60–85 BPM", or "170+ BPM" for the open-ended last preset.
  String get rangeLabel =>
      this == intense ? '$minBpm+ BPM' : '$minBpm–$maxBpm BPM';
}

/// What the user asked Match Your Mood for.
@immutable
sealed class MoodSelection {
  const MoodSelection();
}

class MoodChoice extends MoodSelection {
  final Mood mood;
  const MoodChoice(this.mood);

  @override
  bool operator ==(Object other) => other is MoodChoice && other.mood == mood;

  @override
  int get hashCode => mood.hashCode;
}

/// A BPM range, inclusive.
class TempoChoice extends MoodSelection {
  final int minBpm;
  final int maxBpm;

  const TempoChoice(this.minBpm, this.maxBpm);

  TempoChoice.preset(TempoPreset preset) : this(preset.minBpm, preset.maxBpm);

  /// A custom target from the BPM slider, with a small window around it.
  const TempoChoice.around(int bpm) : this(bpm - 5, bpm + 5);

  bool contains(double bpm) => bpm >= minBpm && bpm <= maxBpm;

  @override
  bool operator ==(Object other) =>
      other is TempoChoice && other.minBpm == minBpm && other.maxBpm == maxBpm;

  @override
  int get hashCode => Object.hash(minBpm, maxBpm);
}
