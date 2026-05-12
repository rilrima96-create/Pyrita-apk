import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Pyrita app-icon — squircle с PNG из ассетов + warm glow overlay.
/// Используется как brand-mark в header'е, в иконке на splash, в profile card.
enum PyAppIconVariant { core, pyrite, fractal }

class PyAppIcon extends StatefulWidget {
  const PyAppIcon({
    super.key,
    this.size = 56,
    this.animated = true,
    this.variant = PyAppIconVariant.core,
    this.tight = true,
  });

  final double size;
  final bool animated;
  final PyAppIconVariant variant;

  /// `tight` версия — кадрированная иконка без полей. `false` — с полями.
  final bool tight;

  @override
  State<PyAppIcon> createState() => _PyAppIconState();
}

class _PyAppIconState extends State<PyAppIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animated) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PyAppIcon old) {
    super.didUpdateWidget(old);
    if (widget.animated && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.animated && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _asset {
    final base = switch (widget.variant) {
      PyAppIconVariant.core => 'icon-a-core',
      PyAppIconVariant.pyrite => 'icon-b-pyrite',
      PyAppIconVariant.fractal => 'icon-c-fractal',
    };
    return 'assets/images/$base${widget.tight ? '-tight' : ''}.png';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final r = s * 0.225;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = widget.animated ? 1.0 + (_ctrl.value * 0.04) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 56,
                  offset: const Offset(0, 24),
                  spreadRadius: -18,
                ),
                const BoxShadow(
                  color: Color(0x2EF5DDA3),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(_asset, fit: BoxFit.cover),
                  // warm glow overlay
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: widget.animated
                            ? 0.6 + _ctrl.value * 0.4
                            : 0.7,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0, 0.04),
                              radius: 0.6,
                              colors: [
                                Color(0x47FFB43C),
                                Color(0x00FFB43C),
                              ],
                              stops: [0.0, 0.7],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // top gloss
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: s * 0.38,
                    child: IgnorePointer(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x1AFFFFFF), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pyrita logo: иконка + слово "Pyrita". Используется в top-bar'ах.
class PyLogo extends StatelessWidget {
  const PyLogo({super.key, this.size = 28, this.withWord = true});

  final double size;
  final bool withWord;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PyAppIcon(size: size, animated: false),
        if (withWord) ...[
          const SizedBox(width: 8),
          Text(
            'Pyrita',
            style: PyDS.font(
              size: size * 0.62,
              weight: FontWeight.w800,
              letterSpacing: -size * 0.013,
              color: PyDS.text,
            ),
          ),
        ],
      ],
    );
  }
}
