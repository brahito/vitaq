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
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _PhotoPage(
          key: ValueKey(widget.items[i].uri),
          photo: widget.items[i],
          photos: widget.photos,
        ),
      ),
    );
  }
}

class _PhotoPage extends StatefulWidget {
  final Photo photo;
  final PhotoRepository photos;

  const _PhotoPage({super.key, required this.photo, required this.photos});

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  late final Future<Uint8List> _bytes = widget.photos.read(widget.photo);

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
              : InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const _Broken(),
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
