import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uvccamera/uvccamera.dart';

import '../../core/device_config.dart';
import '../endoscope_camera.dart';

class EndoscopeCameraAndroid extends EndoscopeCamera {
  final DeviceConfig config;

  EndoscopeStatus _status = EndoscopeStatus.noDevice;
  String? _message;
  UvcCameraDevice? _device;
  UvcCameraController? _controller;
  StreamSubscription<UvcCameraDeviceEvent>? _deviceSub;
  StreamSubscription<UvcCameraButtonEvent>? _buttonSub;
  Timer? _pollTimer;
  final _buttons = StreamController<EndoscopeButtonEvent>.broadcast();

  bool _started = false;
  bool _requesting = false;
  bool _opening = false;
  bool _reopen = false;

  /// Cambia cada vez que se cierra la cámara, para descartar aperturas que
  /// terminan después de una desconexión.
  int _session = 0;

  /// Historial de estados, solo para depurar (se muestra en el letrero amarillo).
  final List<String> history = [];

  EndoscopeCameraAndroid(this.config);

  @override
  EndoscopeStatus get status => _status;

  @override
  String? get message => _message;

  @override
  Stream<EndoscopeButtonEvent> get buttonEvents => _buttons.stream;

  bool _isOurDevice(UvcCameraDevice d) =>
      d.vendorId == config.vendorId && d.productId == config.productId;

  void _set(EndoscopeStatus s, [String? msg]) {
    history.add('${s.name}${msg != null ? ' ($msg)' : ''}');
    debugPrint('[Endoscope] ${history.last}');
    _status = s;
    _message = msg;
    notifyListeners();
  }

  // ---------------------------------------------------------------- start/stop

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (!await UvcCamera.isSupported()) {
      _set(EndoscopeStatus.unsupported, 'Este dispositivo no soporta cámaras USB');
      return;
    }

    _deviceSub = UvcCamera.deviceEventStream.listen(_onDeviceEvent);
    _set(EndoscopeStatus.noDevice);

    // Sondeo de respaldo: busca el endoscopio cada segundo hasta encontrarlo.
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollDevices());
    await _pollDevices();
  }

  @override
  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _closeCamera();
    await _deviceSub?.cancel();
    _deviceSub = null;
    _device = null;
    _started = false;
    _set(EndoscopeStatus.noDevice);
  }

  @override
  void dispose() {
    stop();
    _buttons.close();
    super.dispose();
  }

  // ------------------------------------------------------------- detección

  Future<void> _pollDevices() async {
    if (_device != null) return; // ya lo tenemos
    try {
      final devices = await UvcCamera.getDevices();
      final found = devices.values.where(_isOurDevice);
      if (found.isNotEmpty) {
        _device = found.first;
        await _requestPermissions();
      }
    } catch (e) {
      debugPrint('[Endoscope] poll error: $e');
    }
  }

  void _onDeviceEvent(UvcCameraDeviceEvent event) {
    if (!_isOurDevice(event.device)) return;

    switch (event.type) {
      case UvcCameraDeviceEventType.attached:
        if (_device != null) return; // aviso repetido, ignorar
        _device = event.device;
        _requestPermissions();
      case UvcCameraDeviceEventType.connected:
        _device = event.device;
        _openCamera();
      case UvcCameraDeviceEventType.disconnected:
      case UvcCameraDeviceEventType.detached:
        _closeCamera();
        _device = null; // el sondeo vuelve a buscar
        _set(EndoscopeStatus.noDevice);
    }
  }

  // ------------------------------------------------------------- permisos

  Future<void> _requestPermissions() async {
    if (_requesting) return;
    _requesting = true;
    try {
      _set(EndoscopeStatus.connecting);

      // 1) Permiso de cámara de Android (el plugin lo exige antes del USB)
      var cam = await Permission.camera.status;
      if (!cam.isGranted) cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _device = null;
        _set(EndoscopeStatus.permissionDenied, 'Permiso de cámara denegado');
        return;
      }

      // 2) Permiso USB. Si se concede, llega el evento `connected`.
      final ok = await UvcCamera.requestDevicePermission(_device!);
      if (!ok) {
        _device = null;
        _set(EndoscopeStatus.permissionDenied, 'Permiso USB denegado');
      }
    } catch (e) {
      _device = null;
      _set(EndoscopeStatus.error, 'Error pidiendo permisos: $e');
    } finally {
      _requesting = false;
    }
  }

  // --------------------------------------------------------------- cámara

  Future<void> _openCamera() async {
    if (_controller != null) return; // ya está abierta
    if (_opening) {
      _reopen = true; // se reintenta cuando termine la apertura en curso
      return;
    }
    _opening = true;
    final session = _session;

    try {
      final controller = UvcCameraController(
        device: _device!,
        resolutionPreset: UvcCameraResolutionPreset.max,
      );
      await controller.initialize();

      // Se desconectó mientras abríamos: esta cámara ya no sirve.
      if (session != _session) {
        controller.dispose();
        return;
      }
      // initialize() no lanza el error, solo deja el controlador sin inicializar.
      if (!controller.value.isInitialized) {
        controller.dispose();
        _set(EndoscopeStatus.error, 'No se pudo abrir la cámara');
        return;
      }
      _controller = controller;

      _buttonSub = controller.cameraButtonEvents.listen(
            (e) => _buttons.add(EndoscopeButtonEvent(e.button, e.state)),
      );

      _set(EndoscopeStatus.streaming);
    } catch (e) {
      if (session != _session) return;
      _closeCamera();
      _set(EndoscopeStatus.error, 'No se pudo abrir la cámara: $e');
    } finally {
      _opening = false;
      if (_reopen) {
        _reopen = false;
        if (_controller == null && _device != null) _openCamera();
      }
    }
  }

  void _closeCamera() {
    _session++;
    _buttonSub?.cancel();
    _buttonSub = null;
    _controller?.dispose();
    _controller = null;
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return UvcCameraPreview(c);
  }
}