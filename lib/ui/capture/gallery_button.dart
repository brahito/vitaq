import 'package:flutter/material.dart';

import '../../gallery/photo.dart';
import '../../gallery/photo_repository.dart';
import '../gallery/photo_thumbnail.dart';

/// Acceso a la galería con la miniatura de la última foto. Cuando entra una
/// foto nueva, la miniatura aparece con un pequeño salto: es la confirmación
/// de que quedó guardada.
class GalleryButton extends StatelessWidget {
  final Photo? lastPhoto;
  final PhotoRepository photos;
  final VoidCallback onPressed;

  const GalleryButton({
    super.key,
    required this.lastPhoto,
    required this.photos,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final photo = lastPhoto;
    return Semantics(
      button: true,
      label: 'Abrir galería',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 56,
          height: 56,
          // Borde encima de la miniatura y sin fondo: no quedan esquinas oscuras.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white60, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween<double>(begin: 0.4, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
              child: photo == null
                  ? const Center(
                      key: ValueKey('empty'),
                      child: Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white70,
                      ),
                    )
                  : SizedBox.expand(
                      key: ValueKey(photo.uri),
                      child: PhotoThumbnail(
                        photo: photo,
                        photos: photos,
                        size: 192,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
