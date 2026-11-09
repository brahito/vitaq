String _two(int v) => v.toString().padLeft(2, '0');

/// 20/10/2026 14:30:05
String formatDateTime(DateTime t) =>
    '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// 05:07, o 1:05:07 si pasa de una hora.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = _two(d.inMinutes.remainder(60));
  final s = _two(d.inSeconds.remainder(60));
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
