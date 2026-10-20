import 'package:flutter/material.dart';

class NoDeviceView extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? detail;

  const NoDeviceView({
    super.key,
    this.title = 'No se ha detectado ningún endoscopio conectado',
    this.icon = Icons.videocam_off_outlined,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 96, color: Colors.white54),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}