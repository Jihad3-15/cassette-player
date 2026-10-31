/// Small display helpers shared by the UI.
library;

/// Formats a duration as m:ss (minutes are not wrapped at 60).
String formatDuration(Duration d) {
  final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Formats a total running time, e.g. "42 min" or "1 hr 5 min".
String formatTotal(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} hr ${minutes % 60} min';
}

String songCount(int n) => n == 1 ? '1 song' : '$n songs';
