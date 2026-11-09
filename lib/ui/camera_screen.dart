import 'dart:async';

import 'package:flutter/material.dart';

import '../camera/endoscope_camera.dart';
import '../capture/photo_capture_controller.dart';
import '../capture/video_recording_controller.dart';
import '../core/device_config.dart';
import 'capture/capture_feedback.dart';
import 'capture/gallery_button.dart';
import 'capture/record_controls.dart';
import 'capture/recording_indicator.dart';
import 'capture/shutter_button.dart';
import 'gallery/gallery_screen.dart';
import 'no_device_view.dart';

class CameraScreen extends StatefulWidget {
  final EndoscopeCamera camera;
  final DeviceConfig config;
  final PhotoCaptureController capture;
  final VideoRecordingController recorder;

  const CameraScreen({
    super.key,
    required this.camera,
    required this.config,
    required this.capture,
    required this.recorder,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  StreamSubscription<RecordingEvent>? _videoSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.camera.start();
    widget.capture.refreshLastPhoto();
    // Un video recién guardado pasa a ser la miniatura de la galería.
    _videoSub = widget.recorder.events.listen((e) {
      if (e.type == RecordingEventType.saved && mounted) widget.capture.refreshLastPhoto();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoSub?.cancel();
    widget.camera.stop();
    super.dispose();
  }

  /// La app pasó a segundo plano; otra app pudo tomar la cámara mientras tanto.
  bool _wasInBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wasInBackground = true;
    if (state == AppLifecycleState.resumed) {
      widget.camera.start(); // no hace nada si ya está arrancada
      if (_wasInBackground) {
        _wasInBackground = false;
        widget.camera.reclaim(); // recupera la cámara si otra app la tomó
      }
    }
  }

  Future<void> _openGallery() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GalleryScreen(photos: widget.capture.photos),
      ),
    );
    if (mounted) widget.capture.refreshLastPhoto();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.camera, widget.capture, widget.recorder]),
        builder: (context, _) {
          final cam = widget.camera;
          final streaming = cam.status == EndoscopeStatus.streaming;

          return Stack(
            fit: StackFit.expand,
            children: [
              _content(cam),
              if (streaming) CaptureFeedback(controller: widget.capture, recorder: widget.recorder),
              if (widget.recorder.isActive)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 0, 0),
                      child: RecordingIndicator(recorder: widget.recorder),
                    ),
                  ),
                ),
              _controls(streaming),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(bool streaming) {
    final capture = widget.capture;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GalleryButton(
                lastPhoto: capture.lastPhoto,
                photos: capture.photos,
                onPressed: _openGallery,
              ),
              const Spacer(),
              if (streaming)
                // Grabando también se pueden tomar fotos.
                ShutterButton(
                  onPressed: capture.capture,
                  busy: capture.isCapturing,
                ),
              const Spacer(),
              // Mismo ancho que el botón de la galería: el obturador queda centrado.
              if (streaming || widget.recorder.state != RecordingState.idle)
                RecordControls(recorder: widget.recorder)
              else
                const SizedBox(width: RecordControls.width),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(EndoscopeCamera cam) {
    Widget content;
    switch (cam.status) {
      case EndoscopeStatus.streaming:
        // Doble toque en cualquier parte del video = foto.
        content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.capture.capture,
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 720,
                height: 720,
                child: cam.buildPreview(),
              ),
            ),
          ),
        );
      case EndoscopeStatus.connecting:
        content = const Center(child: CircularProgressIndicator());
      case EndoscopeStatus.noDevice:
        content = const NoDeviceView();
      case EndoscopeStatus.error:
        content = NoDeviceView(
          title: 'No se pudo abrir el endoscopio',
          icon: Icons.warning_amber_rounded,
          detail: cam.message,
        );
      case EndoscopeStatus.permissionDenied:
      case EndoscopeStatus.unsupported:
        content = NoDeviceView(detail: cam.message);
    }

    return content;
  }
}
