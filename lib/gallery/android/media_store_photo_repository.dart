import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../photo.dart';
import '../photo_repository.dart';

/// Álbum "VitaQ" de la galería de Android (Pictures/VitaQ), vía MediaStore.
/// El lado nativo está en android/app/src/main/kotlin/com/vtq/app/PhotoGalleryChannel.kt.
class MediaStorePhotoRepository implements PhotoRepository {
  static const _channel = MethodChannel('vtq/gallery');

  bool? _needsPermission;

  @override
  Future<Photo> save(String tempPath, String name) async {
    await _ensureWriteAccess();
    final map = await _channel.invokeMapMethod<Object?, Object?>('save', {
      'path': tempPath,
      'name': name,
    });
    if (map == null) throw StateError('La galería no devolvió la foto guardada');
    return Photo.fromMap(map);
  }

  @override
  Future<List<Photo>> list() async {
    final items = await _channel.invokeListMethod<Object?>('list') ?? const [];
    return [
      for (final item in items)
        if (item is Map) Photo.fromMap(item),
    ];
  }

  @override
  Future<Uint8List> thumbnail(Photo photo, {int size = 256}) =>
      _bytes('thumbnail', {'uri': photo.uri, 'size': size});

  @override
  Future<Uint8List> read(Photo photo) => _bytes('read', {'uri': photo.uri});

  Future<Uint8List> _bytes(String method, Map<String, Object> args) async {
    final bytes = await _channel.invokeMethod<Uint8List>(method, args);
    if (bytes == null || bytes.isEmpty) throw StateError('Foto vacía');
    return bytes;
  }

  /// Solo Android 9 o anterior necesita permiso para escribir en Pictures.
  Future<void> _ensureWriteAccess() async {
    _needsPermission ??= await _channel.invokeMethod<bool>('needsStoragePermission') ?? false;
    if (!_needsPermission!) return;

    var status = await Permission.storage.status;
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) throw StateError('Permiso de almacenamiento denegado');
  }
}
