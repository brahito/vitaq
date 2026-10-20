import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtq/capture/photo_capture_controller.dart';
import 'package:vtq/core/device_config.dart';
import 'package:vtq/ui/camera_screen.dart';
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

    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(camera: camera, config: kEndoscope, capture: capture),
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

    await tester.tap(find.bySemanticsLabel('Abrir galería'));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryScreen), findsOneWidget);
    expect(find.text('Fotos (2)'), findsOneWidget);

    capture.dispose();
  });
}
