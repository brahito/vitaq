import 'dart:typed_data';

import 'photo.dart';

/// Dónde viven las fotos (patrón Repository): la app no sabe si es la
/// galería de Android, un disco o una prueba.
abstract class PhotoRepository {
  /// Copia el JPEG de [tempPath] al álbum con el nombre [name].
  Future<Photo> save(String tempPath, String name);

  /// Fotos del álbum, la más reciente primero.
  Future<List<Photo>> list();

  /// JPEG pequeño de [photo], de unos [size] píxeles de lado.
  Future<Uint8List> thumbnail(Photo photo, {int size = 256});

  /// JPEG completo de [photo].
  Future<Uint8List> read(Photo photo);
}

/// Placeholder para plataformas sin galería todavía.
class UnsupportedPhotoRepository implements PhotoRepository {
  const UnsupportedPhotoRepository();

  @override
  Future<Photo> save(String tempPath, String name) =>
      Future.error(UnsupportedError('Galería no disponible en esta plataforma'));

  @override
  Future<List<Photo>> list() async => const [];

  @override
  Future<Uint8List> thumbnail(Photo photo, {int size = 256}) =>
      Future.error(UnsupportedError('Galería no disponible en esta plataforma'));

  @override
  Future<Uint8List> read(Photo photo) =>
      Future.error(UnsupportedError('Galería no disponible en esta plataforma'));
}
