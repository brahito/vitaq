import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../capture/photo_capture_controller.dart';

/// Aviso visual y táctil al tomar una foto: un destello breve sobre el video,
/// una vibración corta y un letrero pequeño que se va solo. No bloquea nada:
/// todo deja pasar los toques y no hay que cerrarlo.
class CaptureFeedback extends StatefulWidget {
  final PhotoCaptureController controller;

  const CaptureFeedback({super.key, required this.controller});

  @override
  State<CaptureFeedback> createState() => _CaptureFeedbackState();
}

class _CaptureFeedbackState extends State<CaptureFeedback> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  StreamSubscription<CaptureEvent>? _sub;
  Timer? _hideTimer;
  _Notice? _notice;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(CaptureFeedback old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _sub?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _sub = widget.controller.events.listen(_onEvent);
  }

  void _onEvent(CaptureEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case CaptureEventType.started:
        _haptic(HapticFeedback.lightImpact);
        _flash.forward(from: 0);
      case CaptureEventType.saved:
        _show(const _Notice(Icons.check_circle, 'Foto guardada', Colors.white));
      case CaptureEventType.failed:
        _haptic(HapticFeedback.heavyImpact);
        _show(const _Notice(Icons.error_outline, 'No se pudo guardar la foto', Colors.orangeAccent));
    }
  }

  void _haptic(Future<void> Function() vibrate) {
    vibrate().catchError((Object _) {}); // si el teléfono no vibra, no pasa nada
  }

  void _show(_Notice notice) {
    _hideTimer?.cancel();
    setState(() => _notice = notice);
    _hideTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Destello: sube rápido y se desvanece.
          FadeTransition(
            opacity: TweenSequence<double>([
              TweenSequenceItem(tween: Tween(begin: 0, end: 0.55), weight: 1),
              TweenSequenceItem(tween: Tween(begin: 0.55, end: 0), weight: 3),
            ]).animate(_flash),
            child: const ColoredBox(color: Colors.white),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: notice == null
                      ? const SizedBox.shrink()
                      : _NoticeChip(key: ValueKey(notice.text), notice: notice),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice {
  final IconData icon;
  final String text;
  final Color color;

  const _Notice(this.icon, this.text, this.color);
}

class _NoticeChip extends StatelessWidget {
  final _Notice notice;

  const _NoticeChip({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(notice.icon, size: 18, color: notice.color),
            const SizedBox(width: 8),
            Text(notice.text, style: TextStyle(color: notice.color, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
