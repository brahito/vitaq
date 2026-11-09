import 'package:flutter_test/flutter_test.dart';
import 'package:vtq/camera/endoscope_camera.dart';
import 'package:vtq/capture/video_recording_controller.dart';

import 'photo_capture_controller_test.dart' show FakeCamera, FakeRepository;

void main() {
  late FakeCamera camera;
  late FakeRepository repo;
  late List<String> deleted;
  late VideoRecordingController recorder;
  late List<RecordingEventType> events;

  setUp(() {
    camera = FakeCamera();
    repo = FakeRepository();
    deleted = [];
    events = [];
    recorder = VideoRecordingController(
      camera: camera,
      photos: repo,
      now: () => DateTime(2026, 10, 20, 9, 5, 7, 42),
      deleteTemp: (p) async => deleted.add(p),
      retryDelays: const [Duration.zero, Duration.zero],
    );
    recorder.events.listen((e) => events.add(e.type));
  });

  tearDown(() => recorder.dispose());

  test('graba, pausa, retoma y guarda con el mismo esquema de nombres', () async {
    await recorder.start();
    expect(recorder.state, RecordingState.recording);
    await recorder.pause();
    expect(recorder.state, RecordingState.paused);
    await recorder.resume();
    expect(recorder.state, RecordingState.recording);

    final video = await recorder.stop();
    expect(video?.name, 'VitaQ_20261020_090507_042.mp4');
    expect(video?.isVideo, isTrue);
    expect(recorder.state, RecordingState.idle);
    expect(deleted, ['/cache/REC1.mp4']);
    expect(camera.recordCalls, ['start', 'pause', 'resume', 'stop']);
    await pumpEventQueue();
    expect(events, [RecordingEventType.started, RecordingEventType.saved]);
  });

  test('si no puede empezar avisa, no lanza y se puede reintentar', () async {
    camera.recordError = StateError('sin video');
    await recorder.start();
    expect(recorder.state, RecordingState.idle);
    await pumpEventQueue();
    expect(events, [RecordingEventType.failed]);

    camera.recordError = null;
    await recorder.start();
    expect(recorder.state, RecordingState.recording);
  });

  test('si falla la pausa sigue grabando', () async {
    await recorder.start();
    camera.recordError = StateError('no');
    await recorder.pause();
    expect(recorder.state, RecordingState.recording);
  });

  test('si falla al detener igual intenta guardar lo grabado', () async {
    await recorder.start();
    camera.recordError = StateError('no');
    expect(await recorder.stop(), isNotNull);
    expect(repo.saved, hasLength(1));
  });

  test('si se desconecta grabando guarda el video cuando queda listo', () async {
    await recorder.start();
    repo.failSaves = 2; // el MP4 todavía se está cerrando
    camera.setStatus(EndoscopeStatus.noDevice);
    expect(recorder.state, RecordingState.saving);
    await pumpEventQueue();
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
    expect(repo.saved, hasLength(1));
    expect(recorder.state, RecordingState.idle);
    expect(camera.recordCalls, ['start']);
  });

  test('si nunca queda listo avisa y no borra el temporal', () async {
    await recorder.start();
    repo.saveError = StateError('El video está incompleto');
    expect(await recorder.stop(), isNull);
    expect(deleted, isEmpty);
    expect(recorder.state, RecordingState.idle);
    await pumpEventQueue();
    expect(events.last, RecordingEventType.failed);
  });

  test('ignora órdenes repetidas', () async {
    final first = recorder.start();
    await recorder.start();
    await first;
    expect(camera.recordCalls, ['start']);
    await recorder.resume(); // no está en pausa
    expect(camera.recordCalls, ['start']);
  });
}
