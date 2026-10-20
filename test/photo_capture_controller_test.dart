import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtq/camera/endoscope_camera.dart';
import 'package:vtq/capture/photo_capture_controller.dart';
import 'package:vtq/gallery/cached_photo_repository.dart';
import 'package:vtq/gallery/photo.dart';
import 'package:vtq/gallery/photo_repository.dart';

class FakeCamera extends EndoscopeCamera {
  Completer<String>? pending;
  Object? error;
  int calls = 0;

  @override
  EndoscopeStatus get status => EndoscopeStatus.streaming;
  @override
  String? get message => null;
  @override
  Stream<EndoscopeButtonEvent> get buttonEvents => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> reclaim() async {}
  @override
  Widget buildPreview() => const SizedBox();

  @override
  Future<String> takePicture() {
    calls++;
    if (error != null) return Future.error(error!);
    pending = Completer<String>();
    return pending!.future;
  }
}

class FakeRepository implements PhotoRepository {
  final saved = <Photo>[];
  Object? saveError;
  int thumbnailCalls = 0;
  bool failThumbnail = false;

  @override
  Future<Photo> save(String tempPath, String name) async {
    if (saveError != null) throw saveError!;
    final photo = Photo(uri: 'content://$name', name: name, takenAt: DateTime(2026));
    saved.insert(0, photo);
    return photo;
  }

  @override
  Future<List<Photo>> list() async => List.of(saved);

  @override
  Future<Uint8List> read(Photo photo) async => Uint8List(1);

  @override
  Future<Uint8List> thumbnail(Photo photo, {int size = 256}) async {
    thumbnailCalls++;
    if (failThumbnail) throw StateError('no');
    return Uint8List(1);
  }
}

Photo photoNamed(String id) => Photo(uri: 'content://$id', name: '$id.jpg', takenAt: DateTime(2026));

void main() {
  late FakeCamera camera;
  late FakeRepository repo;
  late List<String> deleted;
  late PhotoCaptureController controller;
  late List<CaptureEventType> events;

  setUp(() {
    camera = FakeCamera();
    repo = FakeRepository();
    deleted = [];
    events = [];
    controller = PhotoCaptureController(
      camera: camera,
      photos: repo,
      now: () => DateTime(2026, 10, 20, 9, 5, 7, 42),
      deleteTemp: (p) async => deleted.add(p),
    );
    controller.events.listen((e) => events.add(e.type));
  });

  tearDown(() => controller.dispose());

  test('guarda la foto con nombre por fecha y borra el temporal', () async {
    final future = controller.capture();
    expect(controller.isCapturing, isTrue);
    camera.pending!.complete('/cache/PIC1.jpg');
    final photo = await future;

    expect(photo?.name, 'VitaQ_20261020_090507_042.jpg');
    expect(controller.lastPhoto, photo);
    expect(controller.isCapturing, isFalse);
    expect(deleted, ['/cache/PIC1.jpg']);
    await pumpEventQueue();
    expect(events, [CaptureEventType.started, CaptureEventType.saved]);
  });

  test('ignora órdenes mientras hay una foto en curso (doble toque repetido)', () async {
    final first = controller.capture();
    expect(await controller.capture(), isNull);
    expect(camera.calls, 1);
    camera.pending!.complete('/cache/PIC1.jpg');
    expect(await first, isNotNull);
  });

  test('un fallo de la cámara no lanza, avisa y permite volver a intentar', () async {
    camera.error = StateError('sin video');
    expect(await controller.capture(), isNull);
    expect(controller.isCapturing, isFalse);
    await pumpEventQueue();
    expect(events, [CaptureEventType.started, CaptureEventType.failed]);

    camera.error = null;
    final again = controller.capture();
    camera.pending!.complete('/cache/PIC2.jpg');
    expect(await again, isNotNull);
  });

  test('un fallo al guardar no lanza y aun así borra el temporal', () async {
    repo.saveError = Exception('disco lleno');
    final future = controller.capture();
    camera.pending!.complete('/cache/PIC1.jpg');
    expect(await future, isNull);
    expect(deleted, ['/cache/PIC1.jpg']);
    expect(controller.lastPhoto, isNull);
  });

  test('si no se puede borrar el temporal la foto igual cuenta', () async {
    final c = PhotoCaptureController(
      camera: camera,
      photos: repo,
      deleteTemp: (_) async => throw Exception('no'),
    );
    final future = c.capture();
    camera.pending!.complete('/cache/PIC1.jpg');
    expect(await future, isNotNull);
    c.dispose();
  });

  test('una foto que termina después de cerrar la pantalla no lanza', () async {
    final c = PhotoCaptureController(camera: camera, photos: repo, deleteTemp: (_) async {});
    final future = c.capture();
    c.dispose();
    camera.pending!.complete('/cache/PIC1.jpg');
    await future;
  });

  test('refreshLastPhoto toma la más reciente', () async {
    await repo.save('x', 'a.jpg');
    await repo.save('x', 'b.jpg');
    await controller.refreshLastPhoto();
    expect(controller.lastPhoto?.name, 'b.jpg');
  });

  group('CachedPhotoRepository', () {
    test('pide cada miniatura una sola vez', () async {
      final cached = CachedPhotoRepository(repo);
      await cached.thumbnail(photoNamed('1'));
      await cached.thumbnail(photoNamed('1'));
      expect(repo.thumbnailCalls, 1);
    });

    test('no guarda los fallos', () async {
      final cached = CachedPhotoRepository(repo);
      repo.failThumbnail = true;
      await expectLater(cached.thumbnail(photoNamed('1')), throwsStateError);
      repo.failThumbnail = false;
      await cached.thumbnail(photoNamed('1'));
      expect(repo.thumbnailCalls, 2);
    });

    test('respeta el límite', () async {
      final cached = CachedPhotoRepository(repo, maxThumbnails: 1);
      await cached.thumbnail(photoNamed('1'));
      await cached.thumbnail(photoNamed('2'));
      await cached.thumbnail(photoNamed('1'));
      expect(repo.thumbnailCalls, 3);
    });
  });
}
