import 'package:flutter/material.dart';

import '../../gallery/photo.dart';
import '../../gallery/photo_repository.dart';
import 'photo_thumbnail.dart';
import 'photo_viewer_screen.dart';

/// Fotos tomadas con VitaQ (álbum Pictures/VitaQ del teléfono).
class GalleryScreen extends StatefulWidget {
  final PhotoRepository photos;

  const GalleryScreen({super.key, required this.photos});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Photo>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.photos.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      debugPrint('[Gallery] no se pudo leer el álbum: $e');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _open(int index) {
    final items = _items;
    if (items == null || index >= items.length) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PhotoViewerScreen(photos: widget.photos, items: items, initialIndex: index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(items == null ? 'Fotos' : 'Fotos (${items.length})'),
      ),
      body: _body(items),
    );
  }

  Widget _body(List<Photo>? items) {
    if (items == null && _error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: 'No se pudieron cargar las fotos',
        action: TextButton(onPressed: _load, child: const Text('Reintentar')),
      );
    }
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return const _Message(
        icon: Icons.photo_library_outlined,
        text: 'Aún no hay fotos.\nToca el botón blanco o toca dos veces la imagen para tomar una.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => _open(i),
          child: Hero(
            tag: items[i].uri,
            child: PhotoThumbnail(photo: items[i], photos: widget.photos, size: 384),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.white38),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ?action,
          ],
        ),
      ),
    );
  }
}
