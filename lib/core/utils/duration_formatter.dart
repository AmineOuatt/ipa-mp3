String formatDurationWithMs(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  final ms = (d.inMilliseconds % 1000) ~/ 100;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$ms';
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

