import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../camera/endoscope_camera.dart';
import '../gallery/photo.dart';
import '../gallery/photo_repository.dart';
import 'capture_file_name.dart';

enum RecordingState {
  idle,

  /// Se pidió empezar y la cámara todavía no confirma.
  starting,
  recording,
  paused,

  /// Cerrando el MP4 y copiándolo al álbum.
  saving,
}

enum RecordingEventType {
  /// Empezó a grabar.
  started,

  /// El video ya está en el álbum.
  saved,

  /// No se pudo empezar, pausar o guardar.
  failed,
}

class RecordingEvent {
  final RecordingEventType type;
  final Photo? video;
  final Object? error;

  const RecordingEvent(this.type, {this.video, this.error});
}

/// Coordina cámara y álbum para grabar video (fachada sobre [EndoscopeCamera]
/// y [PhotoRepository], igual que [PhotoCaptureController] con las fotos).
/// La interfaz llama a [start], [pause], [resume] y [stop] y escucha [events].
///
/// Ningún método lanza: en plena operación un fallo se avisa, no se propaga.
/// Si el endoscopio se desconecta grabando, se guarda lo que alcanzó a grabarse.
class VideoRecordingController extends ChangeNotifier {
  final EndoscopeCamera camera;
  final PhotoRepository photos;
  final DateTime Function() _now;
  final Future<void> Function(String path) _deleteTemp;

  /// Esperas entre intentos de guardar el video: si la cámara se cortó, el
  /// lado nativo todavía puede estar cerrando el MP4.
  final List<Duration> _retryDelays;

  VideoRecordingController({
    required this.camera,
    required this.photos,
    DateTime Function()? now,
    Future<void> Function(String path)? deleteTemp,
    List<Duration>? retryDelays,
  })  : _now = now ?? DateTime.now,
        _deleteTemp = deleteTemp ?? _deleteFile,
        _retryDelays = retryDelays ??
            const [Duration(milliseconds: 500), Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)] {
    camera.addListener(_onCameraChanged);
  }

  final _events = StreamController<RecordingEvent>.broadcast();
  final _clock = Stopwatch();
  RecordingState _state = RecordingState.idle;
  bool _busy = false;
  bool _disposed = false;
  String? _tempPath;
  DateTime? _startedAt;

  /// Avisos para la interfaz (letrero, vibración, miniatura).
  Stream<RecordingEvent> get events => _events.stream;

  RecordingState get state => _state;

  /// Grabando o en pausa: hay un video abierto.
  bool get isActive => _state == RecordingState.recording || _state == RecordingState.paused;

  /// Tiempo grabado, sin contar las pausas.
  Duration get elapsed => _clock.elapsed;

  Future<void> start() async {
    if (_busy || _disposed || _state != RecordingState.idle) return;
    _busy = true;
    _set(RecordingState.starting);
    try {
      final startedAt = _now();
      _tempPath = await camera.startRecording();
      _startedAt = startedAt;
      if (_disposed) return;
      _clock
        ..reset()
        ..start();
      _set(RecordingState.recording);
      _emit(const RecordingEvent(RecordingEventType.started));
    } catch (e, s) {
      debugPrint('[Video] no se pudo empezar: $e\n$s');
      _tempPath = null;
      _set(RecordingState.idle);
      _emit(RecordingEvent(RecordingEventType.failed, error: e));
    } finally {
      _busy = false;
    }
  }

  Future<void> pause() async {
    if (_busy || _state != RecordingState.recording) return;
    _busy = true;
    try {
      await camera.pauseRecording();
      if (_state != RecordingState.recording) return; // se cortó mientras tanto
      _clock.stop();
      _set(RecordingState.paused);
    } catch (e) {
      // Sigue grabando: es mejor que quede de más a perder algo.
      debugPrint('[Video] no se pudo pausar: $e');
      _emit(RecordingEvent(RecordingEventType.failed, error: e));
    } finally {
      _busy = false;
    }
  }

  Future<void> resume() async {
    if (_busy || _state != RecordingState.paused) return;
    _busy = true;
    try {
      await camera.resumeRecording();
      if (_state != RecordingState.paused) return;
      _clock.start();
      _set(RecordingState.recording);
    } catch (e) {
      debugPrint('[Video] no se pudo retomar: $e');
      _emit(RecordingEvent(RecordingEventType.failed, error: e));
    } finally {
      _busy = false;
    }
  }

  /// Termina la grabación y la guarda. Devuelve el video, o null si no se pudo.
  Future<Photo?> stop() async {
    if (_busy || !isActive) return null;
    _busy = true;
    final tempPath = _takeTempPath();
    try {
      try {
        await camera.stopRecording();
      } catch (e) {
        // El MP4 puede haber quedado bien de todos modos; se intenta guardar.
        debugPrint('[Video] falló al detener: $e');
      }
      // Si la cámara se cerró al mismo tiempo, el MP4 puede tardar en quedar listo.
      return await _save(tempPath);
    } finally {
      _busy = false;
    }
  }

  /// El endoscopio dejó de transmitir con un video abierto: el lado nativo
  /// cierra el MP4 y aquí se guarda lo grabado.
  void _onCameraChanged() {
    if (_disposed || !isActive || camera.status == EndoscopeStatus.streaming) return;
    debugPrint('[Video] se cortó la transmisión grabando; se guarda lo grabado');
    _save(_takeTempPath());
  }

  /// Cierra el video abierto (pasa a [RecordingState.saving]) y devuelve su MP4.
  String? _takeTempPath() {
    final tempPath = _tempPath;
    _tempPath = null;
    _clock.stop();
    _set(RecordingState.saving);
    return tempPath;
  }

  Future<Photo?> _save(String? tempPath) async {
    final startedAt = _startedAt ?? _now();
    try {
      if (tempPath == null) throw StateError('No hay archivo de video');
      final name = captureFileName(startedAt, 'mp4');
      final delays = _retryDelays;
      for (var attempt = 0;; attempt++) {
        try {
          final video = await photos.save(tempPath, name);
          await _deleteQuietly(tempPath);
          _emit(RecordingEvent(RecordingEventType.saved, video: video));
          return video;
        } catch (e) {
          if (attempt >= delays.length) rethrow;
          debugPrint('[Video] el video aún no está listo ($e); reintento');
          await Future<void>.delayed(delays[attempt]);
        }
      }
    } catch (e, s) {
      // El MP4 temporal se deja en caché: si algo se puede rescatar, ahí está.
      debugPrint('[Video] no se pudo guardar el video: $e\n$s');
      _emit(RecordingEvent(RecordingEventType.failed, error: e));
      return null;
    } finally {
      _clock.reset();
      _startedAt = null;
      _set(RecordingState.idle);
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await _deleteTemp(path);
    } catch (_) {
      // Es un archivo de caché: si no se borra, Android lo limpia.
    }
  }

  void _set(RecordingState state) {
    if (_state == state) return;
    _state = state;
    if (!_disposed) notifyListeners();
  }

  void _emit(RecordingEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  void dispose() {
    _disposed = true;
    camera.removeListener(_onCameraChanged);
    _events.close();
    super.dispose();
  }
}
