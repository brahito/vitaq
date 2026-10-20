import 'package:flutter/material.dart';

/// Botón redondo para tomar la foto.
class ShutterButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;

  const ShutterButton({super.key, required this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: 'Tomar foto',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: enabled ? Colors.white : Colors.white38, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !enabled
                  ? Colors.white24
                  : busy
                      ? Colors.white54
                      : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
