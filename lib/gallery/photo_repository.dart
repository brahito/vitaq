import 'dart:typed_data';

import 'photo.dart';

/// Dónde viven las fotos y los videos (patrón Repository): la app no sabe si es la
/// galería de Android, un disco o una prueba.
abstract class PhotoRepository {
  /// Copia el JPEG o MP4 de [tempPath] al álbum con el nombre [name]
  /// (la extensión de [name] dice si es foto o video).
  Future<Photo> save(String tempPath, String name);

  /// Fotos y videos del álbum, el más reciente primero.
  Future<List<Photo>> list();

  /// JPEG pequeño de [photo] (de un video, su primer cuadro), de unos [size]
  /// píxeles de lado.
  Future<Uint8List> thumbnail(Photo photo, {int size = 256});

  /// JPEG completo de [photo]. Los videos se reproducen desde [Photo.uri].
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
