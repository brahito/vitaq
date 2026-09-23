import 'package:flutter/widgets.dart';

import '../endoscope_camera.dart';

/// Placeholder mientras no exista implementación nativa (iOS, Windows, macOS).
class EndoscopeCameraUnsupported extends EndoscopeCamera {
  final String platformName;

  EndoscopeCameraUnsupported(this.platformName);

  @override
  EndoscopeStatus get status => EndoscopeStatus.unsupported;

  @override
  String? get message => 'Soporte para $platformName aún no implementado';

  @override
  Stream<EndoscopeButtonEvent> get buttonEvents => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Widget buildPreview() => const SizedBox.shrink();
}