import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const Map<String, String> _countryFlagAssets = {
  'FI': 'assets/images/flags/fi.svg',
  'US': 'assets/images/flags/us.svg',
};

@visibleForTesting
String? pyFlagAssetForCode(String code) =>
    _countryFlagAssets[code.trim().toUpperCase()];

/// Stable country flag widget with local SVG assets for production servers.
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
    final normalizedCode = code.trim().toUpperCase();
    final asset = pyFlagAssetForCode(normalizedCode);
    final flagHeight = size * 0.64;

    return SizedBox.square(
      dimension: size,
      child: Center(
        child: _FlagSurface(
          width: size,
          height: flagHeight,
          child: asset != null
              ? SvgPicture.asset(
                  asset,
                  fit: BoxFit.cover,
                )
              : _FallbackFlag(
                  code: normalizedCode,
                  colors: _fallbackTricolors[normalizedCode] ??
                      const [
                        Color(0xFF222222),
                        Color(0xFF888888),
                        Color(0xFF444444),
                      ],
                ),
        ),
      ),
    );
  }
}

class _FlagSurface extends StatelessWidget {
  const _FlagSurface({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((height * 0.16).clamp(3, 6));

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: const Color(0x33FFFFFF),
                  width: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackFlag extends StatelessWidget {
  const _FallbackFlag({
    required this.code,
    required this.colors,
  });

  final String code;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: Container(color: colors[0])),
            Expanded(child: Container(color: colors[1])),
            Expanded(child: Container(color: colors[2])),
          ],
        ),
        if (code == 'JP')
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.32,
              heightFactor: 0.52,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFFBC002D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        if (code == 'CH') ...[
          const Center(
            child: FractionallySizedBox(
              widthFactor: 0.12,
              heightFactor: 0.58,
              child: ColoredBox(color: Colors.white),
            ),
          ),
          const Center(
            child: FractionallySizedBox(
              widthFactor: 0.42,
              heightFactor: 0.18,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ],
      ],
    );
  }
}
