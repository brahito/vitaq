/// Una foto o un video guardado en el álbum de VitaQ.
class Photo {
  /// Identificador en la galería del teléfono (content://…).
  final String uri;
  final String name;
  final DateTime takenAt;

  /// Es un video (MP4) en vez de una foto.
  final bool isVideo;

  /// Duración del video; cero en las fotos.
  final Duration duration;

  const Photo({
    required this.uri,
    required this.name,
    required this.takenAt,
    this.isVideo = false,
    this.duration = Duration.zero,
  });

  factory Photo.fromMap(Map<Object?, Object?> map) => Photo(
        uri: map['uri'] as String,
        name: (map['name'] as String?) ?? '',
        takenAt: DateTime.fromMillisecondsSinceEpoch((map['takenAt'] as num?)?.toInt() ?? 0),
        isVideo: map['isVideo'] == true,
        duration: Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
      );

  @override
  bool operator ==(Object other) => other is Photo && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
