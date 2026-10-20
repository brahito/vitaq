String _two(int v) => v.toString().padLeft(2, '0');

/// 20/10/2026 14:30:05
String formatDateTime(DateTime t) =>
    '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
