import 'package:flutter/widgets.dart';

enum EndoscopeStatus {
  unsupported,      // plataforma sin implementación todavía
  noDevice,         // no hay endoscopio conectado
  connecting,       // detectado, pidiendo permisos / abriendo
  permissionDenied,
  streaming,        // video en vivo
  error,
}

class EndoscopeButtonEvent {
  final int button;
  final int state;
  const EndoscopeButtonEvent(this.button, this.state);
}

/// Contrato que cumple cada plataforma (Android, iOS, Windows, macOS).
abstract class EndoscopeCamera extends ChangeNotifier {
  EndoscopeStatus get status;
  String? get message;

  /// Empieza a escuchar el dispositivo y a pedir permisos.
  Future<void> start();

  /// Libera todo.
  Future<void> stop();

  /// Widget con el video. Solo válido cuando status == streaming.
  Widget buildPreview();

  /// Botones físicos del endoscopio.
  Stream<EndoscopeButtonEvent> get buttonEvents;
}
