import 'package:flutter/material.dart';

import '../camera/endoscope_camera.dart';
import '../core/device_config.dart';
import 'no_device_view.dart';

class CameraScreen extends StatefulWidget {
  final EndoscopeCamera camera;
  final DeviceConfig config;

  const CameraScreen({super.key, required this.camera, required this.config});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.camera.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.camera.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.camera.start(); // no hace nada si ya está arrancada
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: widget.camera,
        builder: (context, _) {
          final cam = widget.camera;

          Widget content;
          switch (cam.status) {
            case EndoscopeStatus.streaming:
              content = SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(width: 720, height: 720, child: cam.buildPreview()),
                ),
              );
            case EndoscopeStatus.connecting:
              content = const Center(child: CircularProgressIndicator());
            case EndoscopeStatus.noDevice:
              content = NoDeviceView(deviceName: widget.config.displayName);
            case EndoscopeStatus.permissionDenied:
            case EndoscopeStatus.error:
            case EndoscopeStatus.unsupported:
              content = NoDeviceView(deviceName: widget.config.displayName, detail: cam.message);
          }

          // Letrero de depuración (lo quitamos cuando todo funcione)
          return Stack(
            children: [
              content,
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  color: Colors.black54,
                  child: Text(
                    'estado: ${cam.status.name}${cam.message != null ? '\n${cam.message}' : ''}',
                    style: const TextStyle(color: Colors.yellow, fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}