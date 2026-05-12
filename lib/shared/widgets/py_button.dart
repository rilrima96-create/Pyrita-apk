import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Главная gold-кнопка с warm shadow. Pill shape, 1A140A текст.
class PyButtonGold extends StatelessWidget {
  const PyButtonGold({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon,
    this.height = 52,
    this.fontSize = 15,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? icon;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    return Opacity(
      opacity: disabled ? 0.6 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(PyDS.rPill),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: PyDS.gradGold,
              borderRadius: BorderRadius.circular(PyDS.rPill),
              boxShadow: disabled ? null : PyDS.shadowGold,
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFF1A140A),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[icon!, const SizedBox(width: 8)],
                        Text(
                          label,
                          style: PyDS.font(
                            size: fontSize,
                            weight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: const Color(0xFF1A140A),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ghost-кнопка: прозрачный фон + strokeStrong border + светлый текст.
class PyButtonGhost extends StatelessWidget {
  const PyButtonGhost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 52,
    this.fontSize = 14,
    this.color = PyDS.text,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double height;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(PyDS.rPill),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PyDS.rPill),
              border: Border.all(color: PyDS.strokeStrong, width: 1),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 8)],
                  Text(
                    label,
                    style: PyDS.font(
                      size: fontSize,
                      weight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
