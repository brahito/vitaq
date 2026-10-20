import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../camera/endoscope_camera.dart';
import '../gallery/photo.dart';
import '../gallery/photo_repository.dart';

enum CaptureEventType {
  /// Se aceptó la orden y se está tomando el cuadro.
  started,

  /// La foto ya está en el álbum.
  saved,

  /// No se pudo tomar o guardar.
  failed,
}

class CaptureEvent {
  final CaptureEventType type;
  final Photo? photo;
  final Object? error;

  const CaptureEvent(this.type, {this.photo, this.error});
}

/// Coordina cámara y álbum para tomar fotos (fachada sobre [EndoscopeCamera]
/// y [PhotoRepository]). La interfaz solo llama a [capture] y escucha [events].
///
/// [capture] nunca lanza: en plena operación un fallo se avisa, no se propaga.
class PhotoCaptureController extends ChangeNotifier {
  final EndoscopeCamera camera;
  final PhotoRepository photos;
  final DateTime Function() _now;
  final Future<void> Function(String path) _deleteTemp;

  PhotoCaptureController({
    required this.camera,
    required this.photos,
    DateTime Function()? now,
    Future<void> Function(String path)? deleteTemp,
  })  : _now = now ?? DateTime.now,
        _deleteTemp = deleteTemp ?? _deleteFile;

  final _events = StreamController<CaptureEvent>.broadcast();
  bool _capturing = false;
  bool _disposed = false;
  Photo? _lastPhoto;

  /// Avisos para la interfaz (destello, error, miniatura).
  Stream<CaptureEvent> get events => _events.stream;

  /// Hay una foto en curso; mientras tanto se ignoran nuevas órdenes.
  bool get isCapturing => _capturing;

  /// La foto más reciente del álbum, para el botón de la galería.
  Photo? get lastPhoto => _lastPhoto;

  /// Lee la última foto del álbum (al abrir la app o volver de la galería).
  Future<void> refreshLastPhoto() async {
    try {
      final all = await photos.list();
      if (_disposed) return;
      _lastPhoto = all.isEmpty ? null : all.first;
      notifyListeners();
    } catch (e) {
      debugPrint('[Capture] no se pudo leer el álbum: $e');
    }
  }

  /// Toma una foto y la guarda. Devuelve la foto, o null si no se pudo o si
  /// ya había otra en curso (doble toque repetido, por ejemplo).
  Future<Photo?> capture() async {
    if (_capturing || _disposed) return null;
    _capturing = true;
    notifyListeners();
    _emit(const CaptureEvent(CaptureEventType.started));

    String? tempPath;
    try {
      tempPath = await camera.takePicture();
      final photo = await photos.save(tempPath, _fileName(_now()));
      if (_disposed) return photo;
      _lastPhoto = photo;
      _emit(CaptureEvent(CaptureEventType.saved, photo: photo));
      return photo;
    } catch (e, s) {
      debugPrint('[Capture] falló la foto: $e\n$s');
      _emit(CaptureEvent(CaptureEventType.failed, error: e));
      return null;
    } finally {
      if (tempPath != null) {
        try {
          await _deleteTemp(tempPath);
        } catch (_) {
          // Es un archivo de caché: si no se borra, Android lo limpia.
        }
      }
      _capturing = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _emit(CaptureEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// VitaQ_20261020_143005_123.jpg
  static String _fileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return 'VitaQ_${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}_${three(t.millisecond)}.jpg';
  }

  static Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  void dispose() {
    _disposed = true;
    _events.close();
    super.dispose();
  }
}
