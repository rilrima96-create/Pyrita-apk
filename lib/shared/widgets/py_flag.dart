import 'package:flutter/material.dart';

/// Styled circular country flag.
///
/// Frequently used locations get recognizable vector drawings instead of
/// generic tricolor placeholders.
class PyFlag extends StatelessWidget {
  const PyFlag({super.key, required this.code, this.size = 36});

  final String code;
  final double size;

  static const Map<String, List<Color>> _fallbackTricolors = {
    'DE': [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)],
    'NL': [Color(0xFFAE1C28), Color(0xFFFFFFFF), Color(0xFF21468B)],
    'JP': [Color(0xFFFFFFFF), Color(0xFFBC002D), Color(0xFFFFFFFF)],
    'SG': [Color(0xFFED2939), Color(0xFFFFFFFF), Color(0xFFED2939)],
    'SE': [Color(0xFF006AA7), Color(0xFFFECC00), Color(0xFF006AA7)],
    'CH': [Color(0xFFD52B1E), Color(0xFFFFFFFF), Color(0xFFD52B1E)],
    'GB': [Color(0xFF012169), Color(0xFFFFFFFF), Color(0xFFC8102E)],
    'FR': [Color(0xFF0055A4), Color(0xFFFFFFFF), Color(0xFFEF4135)],
  };

  @override
  Widget build(BuildContext context) {
    final normalizedCode = code.toUpperCase();
    if (normalizedCode == 'US' || normalizedCode == 'FI') {
      return _paintedFlag(normalizedCode);
    }

    final colors = _fallbackTricolors[normalizedCode] ??
        const [Color(0xFF222222), Color(0xFF888888), Color(0xFF444444)];
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(child: Container(color: colors[0])),
                Expanded(child: Container(color: colors[1])),
                Expanded(child: Container(color: colors[2])),
              ],
            ),
            if (normalizedCode == 'JP')
              Center(
                child: Container(
                  width: size * 0.42,
                  height: size * 0.42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFBC002D),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (normalizedCode == 'CH') ...[
              Center(
                child: Container(
                  width: size * 0.16,
                  height: size * 0.5,
                  color: Colors.white,
                ),
              ),
              Center(
                child: Container(
                  width: size * 0.5,
                  height: size * 0.16,
                  color: Colors.white,
                ),
              ),
            ],
            const _FlagOutline(),
          ],
        ),
      ),
    );
  }

  Widget _paintedFlag(String normalizedCode) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _CountryFlagPainter(normalizedCode),
            ),
            const _FlagOutline(),
          ],
        ),
      ),
    );
  }
}

class _CountryFlagPainter extends CustomPainter {
  const _CountryFlagPainter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    switch (code) {
      case 'US':
        _paintUnitedStates(canvas, size);
      case 'FI':
        _paintFinland(canvas, size);
    }
  }

  void _paintUnitedStates(Canvas canvas, Size size) {
    final stripeHeight = size.height / 13;
    final red = Paint()..color = const Color(0xFFB22234);
    final white = Paint()..color = Colors.white;
    final blue = Paint()..color = const Color(0xFF3C3B6E);

    for (var i = 0; i < 13; i += 1) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripeHeight, size.width, stripeHeight),
        i.isEven ? red : white,
      );
    }

    final canton = Rect.fromLTWH(0, 0, size.width * 0.54, stripeHeight * 7);
    canvas.drawRect(canton, blue);

    final starPaint = Paint()..color = Colors.white;
    final dotRadius = size.width * 0.018;
    final startX = size.width * 0.075;
    final startY = stripeHeight * 0.78;
    final gapX = size.width * 0.08;
    final gapY = stripeHeight * 0.72;

    for (var row = 0; row < 5; row += 1) {
      for (var col = 0; col < 4; col += 1) {
        canvas.drawCircle(
          Offset(startX + col * gapX, startY + row * gapY),
          dotRadius,
          starPaint,
        );
      }
    }
  }

  void _paintFinland(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final blue = Paint()..color = const Color(0xFF003580);
    canvas.drawRect(Offset.zero & size, white);

    final verticalX = size.width * 0.34;
    final crossWidth = size.width * 0.19;
    canvas.drawRect(
      Rect.fromLTWH(verticalX, 0, crossWidth, size.height),
      blue,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.40, size.width, crossWidth),
      blue,
    );
  }

  @override
  bool shouldRepaint(covariant _CountryFlagPainter oldDelegate) {
    return oldDelegate.code != code;
  }
}

class _FlagOutline extends StatelessWidget {
  const _FlagOutline();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0x2EFFFFFF),
            width: 0.6,
          ),
        ),
      ),
    );
  }
}
