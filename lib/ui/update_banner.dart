import 'package:flutter/material.dart';

import '../core/app_updater.dart';

/// Aviso pequeño arriba a la derecha: muestra la descarga en curso y, cuando
/// la APK está lista, un botón "Instalar". No se instala en mitad de un uso
/// de la cámara: el usuario elige el momento.
class UpdateBanner extends StatelessWidget {
  final AppUpdater updater;

  const UpdateBanner({super.key, required this.updater});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final version = updater.newVersionName != null ? ' ${updater.newVersionName}' : '';
        Widget child;
        switch (updater.status) {
          case UpdateStatus.idle:
          case UpdateStatus.error:
            return const SizedBox.shrink();
          case UpdateStatus.downloading:
            child = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: updater.progress > 0 ? updater.progress : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Descargando actualización$version… ${(updater.progress * 100).round()}%'),
              ],
            );
          case UpdateStatus.ready:
            child = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update, size: 20),
                const SizedBox(width: 10),
                Text('Versión$version lista'),
                const SizedBox(width: 12),
                FilledButton(onPressed: updater.install, child: const Text('Instalar')),
              ],
            );
        }

        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
