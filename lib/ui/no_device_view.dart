import 'package:flutter/material.dart';

class NoDeviceView extends StatelessWidget {
  final String deviceName;
  final String? detail;

  const NoDeviceView({super.key, required this.deviceName, this.detail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 96, color: Colors.white54),
            const SizedBox(height: 24),
            Text(
              'No se ha detectado el dispositivo $deviceName',
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