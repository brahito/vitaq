/// Una foto guardada en el álbum de VitaQ.
class Photo {
  /// Identificador de la foto en la galería del teléfono (content://…).
  final String uri;
  final String name;
  final DateTime takenAt;

  const Photo({required this.uri, required this.name, required this.takenAt});

  factory Photo.fromMap(Map<Object?, Object?> map) => Photo(
        uri: map['uri'] as String,
        name: (map['name'] as String?) ?? '',
        takenAt: DateTime.fromMillisecondsSinceEpoch((map['takenAt'] as num?)?.toInt() ?? 0),
      );

  @override
  bool operator ==(Object other) => other is Photo && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
