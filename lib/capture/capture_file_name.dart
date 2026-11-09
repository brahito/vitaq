/// Nombre con que se guarda una captura en el álbum, según la hora en que se
/// tomó: VitaQ_20261020_143005_123.jpg (o .mp4 para los videos).
String captureFileName(DateTime t, String extension) {
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return 'VitaQ_${t.year}${two(t.month)}${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}_${three(t.millisecond)}.$extension';
}
