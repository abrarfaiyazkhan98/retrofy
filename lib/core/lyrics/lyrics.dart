import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Where lyrics came from, shown as attribution under the lyrics.
enum LyricsSource { embedded, lrcFile, lrclib }

@immutable
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);
}

/// Lyrics for one track: timestamped [lines] when synced, otherwise [plain].
@immutable
class Lyrics {
  final List<LyricLine> lines;
  final String? plain;
  final LyricsSource source;
  final bool instrumental;

  const Lyrics({
    this.lines = const [],
    this.plain,
    required this.source,
    this.instrumental = false,
  });

  bool get isSynced => lines.isNotEmpty;

  bool get isEmpty => !isSynced && (plain?.trim().isEmpty ?? true);

  /// Lyrics text in either form: plain text, or LRC/plain from tags or
  /// files. Returns null when there is nothing to show.
  static Lyrics? parse(String? text, LyricsSource source) {
    if (text == null || text.trim().isEmpty) return null;
    final lines = parseLrc(text);
    return Lyrics(
      lines: lines,
      plain: lines.isEmpty ? text.trim() : null,
      source: source,
    );
  }

  /// Index of the line being sung at [position], or -1 before the first.
  int indexAt(Duration position) {
    var low = 0, high = lines.length - 1, found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].time <= position) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _offsetTag = RegExp(
  r'^\[offset:\s*([+-]?\d+)\s*\]',
  caseSensitive: false,
);

/// Parses LRC text. A line may carry several timestamps; `[offset:ms]`
/// shifts every line (positive = earlier, per the LRC convention); other
/// `[tag:value]` lines are metadata and ignored. Returns an empty list when
/// [text] has no timestamps (plain lyrics).
List<LyricLine> parseLrc(String text) {
  var offset = 0;
  final lines = <LyricLine>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final offsetMatch = _offsetTag.firstMatch(line);
    if (offsetMatch != null) {
      offset = int.parse(offsetMatch.group(1)!);
      continue;
    }
    final tags = <Duration>[];
    var rest = line;
    while (true) {
      final match = _timeTag.matchAsPrefix(rest);
      if (match == null) break;
      final fraction = match.group(3) ?? '0';
      // ".5" is half a second, ".05" fifty and ".005" five milliseconds.
      final millis = int.parse(fraction.padRight(3, '0').substring(0, 3));
      tags.add(
        Duration(
          minutes: int.parse(match.group(1)!),
          seconds: int.parse(match.group(2)!),
          milliseconds: millis,
        ),
      );
      rest = rest.substring(match.end);
    }
    final words = rest.trim();
    for (final time in tags) {
      final shifted = time - Duration(milliseconds: offset);
      lines.add(LyricLine(shifted.isNegative ? Duration.zero : shifted, words));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}
