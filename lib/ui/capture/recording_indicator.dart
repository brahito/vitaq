import 'dart:async';

import 'package:flutter/material.dart';

import '../../capture/video_recording_controller.dart';
import '../format.dart';

/// Letrero arriba a la izquierda mientras hay un video abierto: punto rojo
/// que parpadea y el tiempo grabado, o "En pausa".
class RecordingIndicator extends StatefulWidget {
  final VideoRecordingController recorder;

  const RecordingIndicator({super.key, required this.recorder});

  @override
  State<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<RecordingIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paused = widget.recorder.state == RecordingState.paused;
    final elapsed = widget.recorder.elapsed;
    // Grabando, el punto parpadea cada medio segundo; en pausa queda fijo.
    final dotOn = paused || DateTime.now().millisecond < 500;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                paused ? Icons.pause : Icons.fiber_manual_record,
                size: 16,
                color: paused ? Colors.white : (dotOn ? Colors.redAccent : Colors.transparent),
              ),
              const SizedBox(width: 6),
              Text(
                paused ? '${formatDuration(elapsed)}  En pausa' : formatDuration(elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
