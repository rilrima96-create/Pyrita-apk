import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Состояние VPN-соединения.
enum ConnState { idle, connecting, active }

/// Sonar-hero: radial sweep + детектируемые точки + центральный glow.
/// CSS-аналог: `PyPulse` из widgets.jsx (variant pulse). 3 анимации:
///   * rings — расходящаяся рябь 2.4s, 4 кольца со staggered phase
///   * sweep — вращающийся wedge 4.5s linear (только не idle)
///   * breath — центральный glow «дышит» 2.4s (только не idle)
class PyPulse extends StatefulWidget {
  const PyPulse({super.key, this.size = 232, this.state = ConnState.active});

  final double size;
  final ConnState state;

  @override
  State<PyPulse> createState() => _PyPulseState();
}

class _PyPulseState extends State<PyPulse> with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final AnimationController _sweepCtrl;
  late final AnimationController _breathCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _updateAnimations();
  }

  @override
  void didUpdateWidget(covariant PyPulse old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _updateAnimations();
  }

  void _updateAnimations() {
    final on = widget.state != ConnState.idle;
    if (on) {
      if (!_ringCtrl.isAnimating) _ringCtrl.repeat();
      if (!_sweepCtrl.isAnimating) _sweepCtrl.repeat();
      if (!_breathCtrl.isAnimating) _breathCtrl.repeat(reverse: true);
    } else {
      _ringCtrl.stop();
      _sweepCtrl.stop();
      _breathCtrl.stop();
    }
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _sweepCtrl.dispose();
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: Listenable.merge([_ringCtrl, _sweepCtrl, _breathCtrl]),
          builder: (context, _) {
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _PulsePainter(
                state: widget.state,
                ringT: _ringCtrl.value,
                sweepT: _sweepCtrl.value,
                breathT: _breathCtrl.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.state,
    required this.ringT,
    required this.sweepT,
    required this.breathT,
  });

  final ConnState state;
  final double ringT;
  final double sweepT;
  final double breathT;

  static const _nodes = <_Node>[
    _Node(angleDeg: 25, dist: 70, phase: 0.0),
    _Node(angleDeg: 80, dist: 55, phase: 0.6),
    _Node(angleDeg: 145, dist: 78, phase: 1.3),
    _Node(angleDeg: 200, dist: 50, phase: 0.9),
    _Node(angleDeg: 265, dist: 72, phase: 1.9),
    _Node(angleDeg: 320, dist: 60, phase: 2.4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 200; // canvas сделан под 200×200 viewBox
    final intensity = switch (state) {
      ConnState.idle => 0.18,
      ConnState.connecting => 0.55,
      ConnState.active => 1.0,
    };
    final on = state != ConnState.idle;

    // 1. background warm glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(255, 180, 60, 0.20 * intensity),
          const Color(0x00FFB43C),
        ],
        stops: const [0.0, 0.65],
      ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.55))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(c, size.width * 0.55, glowPaint);

    // 2. background grid: 3 концентрических круга + cross
    final gridPaint = Paint()
      ..color = const Color(0x29C9A875) // 0.16
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 * scale;
    for (final r in [32.0, 56.0, 80.0]) {
      canvas.drawCircle(c, r * scale, gridPaint);
    }
    canvas.drawLine(
      Offset(c.dx, c.dy - 80 * scale),
      Offset(c.dx, c.dy + 80 * scale),
      gridPaint,
    );
    canvas.drawLine(
      Offset(c.dx - 80 * scale, c.dy),
      Offset(c.dx + 80 * scale, c.dy),
      gridPaint,
    );

    // 3. outgoing pulse rings — 4 кольца, staggered 0.25
    for (int i = 0; i < 4; i++) {
      // ring i фаза t = (ringT + i*0.25) mod 1
      final t = on ? ((ringT + i * 0.25) % 1.0) : 0.0;
      final r = (20 + t * (4.6 - 1.0) * 20) * scale; // от ~20 до ~92
      final fadeOut = on ? (t < 0.8 ? 0.95 * (1 - t / 0.8) : 0.0) : 0.18;
      final ringPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5DDA3), Color(0xFF7A5F35)],
        ).createShader(Rect.fromCircle(center: c, radius: r))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (on ? 1.1 : 0.6) * scale
        ..color = Colors.white.withValues(alpha: fadeOut.clamp(0.0, 1.0));
      // shader не учитывает alpha сам по себе — мажорим opacity через layer
      canvas.saveLayer(
        Rect.fromCircle(center: c, radius: r + 4),
        Paint()
          ..color = Colors.white.withValues(alpha: fadeOut.clamp(0.0, 1.0)),
      );
      canvas.drawCircle(c, r, ringPaint);
      canvas.restore();
    }

    // 4. sweep wedge — вращается. Сектор от центра, 28°
    if (on) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(sweepT * 2 * math.pi);
      final sweepRect = Rect.fromCircle(
        center: Offset.zero,
        radius: 80 * scale,
      );
      final sweepPath = Path()
        ..moveTo(0, 0)
        ..arcTo(sweepRect, 0, -28 * math.pi / 180, false)
        ..close();
      final sweepPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x00F5DDA3), Color(0x0DF5DDA3), Color(0x8CF5DDA3)],
          stops: [0.0, 0.7, 1.0],
        ).createShader(sweepRect);
      canvas.drawPath(sweepPath, sweepPaint);
      canvas.restore();
    }

    // 5. detected nodes — пульсируют
    for (final n in _nodes) {
      final theta = n.angleDeg * math.pi / 180;
      final p = Offset(
        c.dx + math.cos(theta) * n.dist * scale,
        c.dy + math.sin(theta) * n.dist * scale,
      );
      // breath cycle на каждой ноде со своей фазой
      final localT = on ? ((breathT + n.phase / 2.4) % 1.0) : 0.5;
      final nodeScale =
          on ? (1.0 + math.sin(localT * 2 * math.pi) * 0.18) : 1.0;
      final nodeAlpha = on ? 1.0 : 0.4;
      // outer halo
      final haloPaint = Paint()
        ..color = const Color(0xFFF5DDA3).withValues(alpha: 0.25 * nodeAlpha);
      canvas.drawCircle(p, 5 * scale * nodeScale, haloPaint);
      // core dot
      final dotPaint = Paint()
        ..color = const Color(0xFFFFE08A).withValues(alpha: nodeAlpha);
      canvas.drawCircle(p, 2.4 * scale * nodeScale, dotPaint);
    }

    // 6. central pyrite glow + hex glyph
    final breathScale = on ? (1.0 + math.sin(breathT * math.pi) * 0.04) : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(breathScale);

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF5C8),
          const Color(0xFFFFC04A),
          Color.fromRGBO(229, 90, 24, 0.7),
          const Color(0x00E55A18),
        ],
        stops: const [0.0, 0.22, 0.55, 1.0],
      ).createShader(
        Rect.fromCircle(center: Offset.zero, radius: 22 * scale),
      );
    canvas.drawCircle(
      Offset.zero,
      22 * scale,
      corePaint
        ..color = Colors.white.withValues(alpha: (0.5 + intensity * 0.5)),
    );

    // hex pyrite glyph (scale 0.45)
    final hex = Path()
      ..moveTo(0, -22 * scale * 0.45)
      ..lineTo(19 * scale * 0.45, -7 * scale * 0.45)
      ..lineTo(19 * scale * 0.45, 15 * scale * 0.45)
      ..lineTo(0, 22 * scale * 0.45)
      ..lineTo(-19 * scale * 0.45, 15 * scale * 0.45)
      ..lineTo(-19 * scale * 0.45, -7 * scale * 0.45)
      ..close();
    final hexFillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF5DDA3), Color(0xFF7A5F35)],
      ).createShader(
        Rect.fromCircle(center: Offset.zero, radius: 22 * scale * 0.45),
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(hex, hexFillPaint);
    final hexStrokePaint = Paint()
      ..color = const Color(0xFFFAEAB7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * scale * 0.45
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(hex, hexStrokePaint);
    // vertical line
    final vLine = Paint()
      ..color = const Color(0xFFF5DDA3).withValues(alpha: 0.4)
      ..strokeWidth = 0.6 * scale * 0.45;
    canvas.drawLine(
      Offset(0, -22 * scale * 0.45),
      Offset(0, 22 * scale * 0.45),
      vLine,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) =>
      old.ringT != ringT ||
      old.sweepT != sweepT ||
      old.breathT != breathT ||
      old.state != state;
}

class _Node {
  const _Node({
    required this.angleDeg,
    required this.dist,
    required this.phase,
  });
  final double angleDeg;
  final double dist;
  final double phase;
}
