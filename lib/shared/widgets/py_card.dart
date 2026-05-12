import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Стандартная Pyrita-карточка: bg1 + subtle gold gradient overlay + stroke.
class PyCard extends StatelessWidget {
  const PyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PyDS.sp4),
    this.radius = PyDS.rLg,
    this.gradient,
    this.border,
    this.shadow = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Gradient? gradient;
  final BoxBorder? border;
  final bool shadow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: gradient == null ? PyDS.bg1 : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: border ?? Border.all(color: PyDS.stroke, width: 1),
      boxShadow: shadow ? PyDS.shadowCard : null,
    );

    final inner = Container(
      padding: padding,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: gradient == null ? PyDS.gradCard : null,
      ),
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return inner;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: inner,
      ),
    );
  }
}

/// Pyrita chip — uppercase pill с лёгким border.
class PyChip extends StatelessWidget {
  const PyChip({
    super.key,
    required this.label,
    this.leading,
    this.color,
    this.background,
    this.borderColor,
  });

  final String label;
  final Widget? leading;
  final Color? color;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? PyDS.bg2,
        borderRadius: BorderRadius.circular(PyDS.rPill),
        border: Border.all(color: borderColor ?? PyDS.stroke, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Text(
            label.toUpperCase(),
            style: PyDS.font(
              size: 10.5,
              weight: FontWeight.w600,
              letterSpacing: 0.6,
              color: color ?? PyDS.textMute,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient gold text. Использует ShaderMask поверх обычного Text.
class PyTextGold extends StatelessWidget {
  const PyTextGold({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => PyDS.gradTextGold.createShader(rect),
      child: Text(
        text,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
        textAlign: textAlign,
      ),
    );
  }
}
