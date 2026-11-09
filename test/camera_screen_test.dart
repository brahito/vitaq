import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtq/capture/photo_capture_controller.dart';
import 'package:vtq/capture/video_recording_controller.dart';
import 'package:vtq/core/device_config.dart';
import 'package:vtq/ui/camera_screen.dart';
import 'package:vtq/ui/capture/recording_indicator.dart';
import 'package:vtq/ui/capture/shutter_button.dart';
import 'package:vtq/ui/gallery/gallery_screen.dart';

import 'photo_capture_controller_test.dart' show FakeCamera, FakeRepository;

class InstantCamera extends FakeCamera {
  @override
  Future<String> takePicture() async {
    calls++;
    return '/cache/PIC$calls.jpg';
  }

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.blue);
}

void main() {
  testWidgets('el botón y el doble toque toman fotos; la galería las muestra', (tester) async {
    final camera = InstantCamera();
    final repo = FakeRepository();
    var tick = 0;
    final capture = PhotoCaptureController(
      camera: camera,
      photos: repo,
      now: () => DateTime(2026, 1, 1).add(Duration(seconds: tick++)),
      deleteTemp: (_) async {},
    );
    final recorder = VideoRecordingController(
      camera: camera,
      photos: repo,
      now: () => DateTime(2026, 1, 1).add(Duration(seconds: tick++)),
      deleteTemp: (_) async {},
    );

    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(camera: camera, config: kEndoscope, capture: capture, recorder: recorder),
    ));
    await tester.pump();

    await tester.tap(find.byType(ShutterButton));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(find.text('Foto guardada'), findsOneWidget);

    final center = tester.getCenter(find.byType(Scaffold));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(2));

    // Toque simple: no toma foto.
    await tester.tapAt(center);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(repo.saved, hasLength(2));

    // Video: empezar, foto grabando, pausar, retomar y detener.
    await tester.tap(find.bySemanticsLabel('Grabar video'));
    await tester.pump();
    expect(recorder.state, RecordingState.recording);
    expect(find.byType(RecordingIndicator), findsOneWidget);

    await tester.tap(find.byType(ShutterButton));
    await tester.pump();
    expect(repo.saved, hasLength(3));

    await tester.tap(find.bySemanticsLabel('Pausar grabación'));
    await tester.pump();
    expect(find.textContaining('En pausa'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Retomar grabación'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Detener grabación'));
    await tester.pump();
    await tester.pump();
    expect(camera.recordCalls, ['start', 'pause', 'resume', 'stop']);
    expect(repo.saved.first.isVideo, isTrue);
    expect(find.byType(RecordingIndicator), findsNothing);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Abrir galería'));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryScreen), findsOneWidget);
    expect(find.text('Galería (4)'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);

    recorder.dispose();
    capture.dispose();
  });
}
