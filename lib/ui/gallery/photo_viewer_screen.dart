import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../gallery/photo.dart';
import '../../gallery/photo_repository.dart';
import '../format.dart';
import 'photo_thumbnail.dart';

/// Foto a pantalla completa. Se desliza entre fotos y se hace zoom con dos dedos.
class PhotoViewerScreen extends StatefulWidget {
  final PhotoRepository photos;
  final List<Photo> items;
  final int initialIndex;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  // Con la foto ampliada o con dos dedos en pantalla se desactiva el
  // deslizamiento entre fotos; si no, el PageView se queda con el gesto de
  // pellizco y el zoom nunca llega a la foto.
  bool _zoomed = false;
  int _pointers = 0;

  void _setPointers(int value) {
    final before = _pointers >= 2;
    _pointers = value < 0 ? 0 : value;
    if (before != (_pointers >= 2)) setState(() {});
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        title: Text(
          '${formatDateTime(photo.takenAt)}   ${_index + 1}/${widget.items.length}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: Listener(
        onPointerDown: (_) => _setPointers(_pointers + 1),
        onPointerUp: (_) => _setPointers(_pointers - 1),
        onPointerCancel: (_) => _setPointers(_pointers - 1),
        child: PageView.builder(
          controller: _pages,
          physics: _zoomed || _pointers >= 2
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() {
            _index = i;
            _zoomed = false;
          }),
          itemBuilder: (context, i) => _PhotoPage(
            key: ValueKey(widget.items[i].uri),
            photo: widget.items[i],
            photos: widget.photos,
            onZoomChanged: (zoomed) {
              if (mounted && zoomed != _zoomed) setState(() => _zoomed = zoomed);
            },
          ),
        ),
      ),
    );
  }
}

class _PhotoPage extends StatefulWidget {
  final Photo photo;
  final PhotoRepository photos;
  final ValueChanged<bool> onZoomChanged;

  const _PhotoPage({
    super.key,
    required this.photo,
    required this.photos,
    required this.onZoomChanged,
  });

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  late final Future<Uint8List> _bytes = widget.photos.read(widget.photo);
  final _transform = TransformationController();
  bool _zoomed = false;
  Offset _doubleTapAt = Offset.zero;

  static const _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  /// Doble toque: amplía donde se tocó, o vuelve al tamaño normal.
  void _toggleZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    const s = _doubleTapScale;
    final p = _doubleTapAt;
    // Escala s con el punto tocado fijo en pantalla (matriz por columnas).
    _transform.value = Matrix4(
      s, 0, 0, 0, //
      0, s, 0, 0, //
      0, 0, 1, 0, //
      -p.dx * (s - 1), -p.dy * (s - 1), 0, 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) return const _Broken();
        final bytes = snap.data;
        return Hero(
          tag: widget.photo.uri,
          child: bytes == null
              // Mientras carga la foto completa se ve la miniatura.
              ? Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: PhotoThumbnail(photo: widget.photo, photos: widget.photos),
                  ),
                )
              : GestureDetector(
                  onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                  onDoubleTap: _toggleZoom,
                  child: InteractiveViewer(
                    transformationController: _transform,
                    maxScale: 8,
                    child: Center(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const _Broken(),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 72, color: Colors.white38),
            SizedBox(height: 12),
            Text('No se pudo abrir la foto', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
}
