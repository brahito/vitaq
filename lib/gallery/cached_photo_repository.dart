import 'dart:typed_data';

import 'photo.dart';
import 'photo_repository.dart';

/// Decorador que recuerda las miniaturas ya cargadas, para que la galería y
/// el botón de la cámara no las pidan una y otra vez.
class CachedPhotoRepository implements PhotoRepository {
  final PhotoRepository _inner;
  final int maxThumbnails;

  // El mapa conserva el orden de inserción: el primero es el menos usado.
  final Map<String, Future<Uint8List>> _thumbnails = {};

  CachedPhotoRepository(this._inner, {this.maxThumbnails = 300});

  @override
  Future<Photo> save(String tempPath, String name) => _inner.save(tempPath, name);

  @override
  Future<List<Photo>> list() => _inner.list();

  @override
  Future<Uint8List> read(Photo photo) => _inner.read(photo);

  @override
  Future<Uint8List> thumbnail(Photo photo, {int size = 256}) {
    final key = '$size|${photo.uri}';
    final cached = _thumbnails.remove(key);
    if (cached != null) {
      _thumbnails[key] = cached; // pasa a ser el más reciente
      return cached;
    }

    final future = _inner.thumbnail(photo, size: size);
    _thumbnails[key] = future;
    // Un fallo no se guarda: la próxima vez se vuelve a intentar.
    future.catchError((Object _) {
      if (identical(_thumbnails[key], future)) _thumbnails.remove(key);
      return Uint8List(0);
    });
    while (_thumbnails.length > maxThumbnails) {
      _thumbnails.remove(_thumbnails.keys.first);
    }
    return future;
  }
}
