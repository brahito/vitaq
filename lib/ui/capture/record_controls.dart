import 'package:flutter/material.dart';

import '../../capture/video_recording_controller.dart';

/// Botones de video para la esquina: una cámara pequeña para empezar y,
/// grabando, pausar/retomar encima de detener. Siempre miden [width] de ancho
/// para que el obturador quede centrado.
class RecordControls extends StatelessWidget {
  final VideoRecordingController recorder;

  static const width = 56.0;

  const RecordControls({super.key, required this.recorder});

  @override
  Widget build(BuildContext context) {
    final state = recorder.state;
    final active = recorder.isActive;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active) ...[
            _RoundButton(
              label: state == RecordingState.paused ? 'Retomar grabación' : 'Pausar grabación',
              onPressed: state == RecordingState.paused ? recorder.resume : recorder.pause,
              child: Icon(
                state == RecordingState.paused ? Icons.fiber_manual_record : Icons.pause,
                color: state == RecordingState.paused ? Colors.redAccent : Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            _RoundButton(
              label: 'Detener grabación',
              onPressed: recorder.stop,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ] else
            _RoundButton(
              label: 'Grabar video',
              // Mientras empieza o se guarda, no acepta otra orden.
              onPressed: state == RecordingState.idle ? recorder.start : null,
              child: state == RecordingState.idle
                  ? const Icon(Icons.videocam, color: Colors.white, size: 26)
                  : const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Botón redondo de 52 px, un poco más chico que el obturador.
class _RoundButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  const _RoundButton({required this.label, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black38,
            border: Border.all(color: onPressed == null ? Colors.white38 : Colors.white70, width: 2),
          ),
          child: child,
        ),
      ),
    );
  }
}
