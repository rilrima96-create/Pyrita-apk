import 'package:flutter/material.dart';

/// Стилизованный круглый «флажок» страны: три цветные полосы поверх круглого
/// клипа. Не пиксель-точный, для UI достаточно.
class PyFlag extends StatelessWidget {
  const PyFlag({super.key, required this.code, this.size = 36});

  final String code;
  final double size;

  static const Map<String, List<Color>> _flags = {
    'DE': [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)],
    'NL': [Color(0xFFAE1C28), Color(0xFFFFFFFF), Color(0xFF21468B)],
    'US': [Color(0xFFB22234), Color(0xFFFFFFFF), Color(0xFF3C3B6E)],
    'JP': [Color(0xFFFFFFFF), Color(0xFFBC002D), Color(0xFFFFFFFF)],
    'SG': [Color(0xFFED2939), Color(0xFFFFFFFF), Color(0xFFED2939)],
    'SE': [Color(0xFF006AA7), Color(0xFFFECC00), Color(0xFF006AA7)],
    'CH': [Color(0xFFD52B1E), Color(0xFFFFFFFF), Color(0xFFD52B1E)],
    'GB': [Color(0xFF012169), Color(0xFFFFFFFF), Color(0xFFC8102E)],
    'FR': [Color(0xFF0055A4), Color(0xFFFFFFFF), Color(0xFFEF4135)],
    'FI': [Color(0xFFFFFFFF), Color(0xFF003580), Color(0xFFFFFFFF)],
  };

  @override
  Widget build(BuildContext context) {
    final c = _flags[code] ??
        const [Color(0xFF222222), Color(0xFF888888), Color(0xFF444444)];
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(child: Container(color: c[0])),
                Expanded(child: Container(color: c[1])),
                Expanded(child: Container(color: c[2])),
              ],
            ),
            // JP — красный круг по центру
            if (code == 'JP')
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
            // CH — белый крест
            if (code == 'CH') ...[
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
            // outline для нежного бордюра
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x2EFFFFFF),
                    width: 0.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
