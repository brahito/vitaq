import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../gallery/photo.dart';
import '../../gallery/photo_repository.dart';

/// Miniatura de una foto del álbum. Si no carga, muestra un ícono en su lugar.
class PhotoThumbnail extends StatefulWidget {
  final Photo photo;
  final PhotoRepository photos;
  final int size;

  const PhotoThumbnail({super.key, required this.photo, required this.photos, this.size = 256});

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(PhotoThumbnail old) {
    super.didUpdateWidget(old);
    if (old.photo != widget.photo || old.size != widget.size) _bytes = _load();
  }

  Future<Uint8List> _load() => widget.photos.thumbnail(widget.photo, size: widget.size);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) return const _Placeholder(icon: Icons.broken_image_outlined);
        final bytes = snap.data;
        if (bytes == null) return const _Placeholder();
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const _Placeholder(icon: Icons.broken_image_outlined),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  final IconData? icon;

  const _Placeholder({this.icon});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white10,
      child: icon == null ? null : Center(child: Icon(icon, color: Colors.white38)),
    );
  }
}
