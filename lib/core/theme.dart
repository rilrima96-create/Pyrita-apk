import 'package:flutter/material.dart';

/// Pyrita Design System — токены из `pyrita-app-v2/pyrita.css`.
/// Тёмная warm-mineral палитра + champagne gold. Брендовое ядро.
class PyDS {
  PyDS._();

  // ── core surfaces ─────────────────────────────────────────────
  static const Color ink = Color(0xFF0C0907);
  static const Color bg = Color(0xFF14100C);
  static const Color bg1 = Color(0xFF1A1410);
  static const Color bg2 = Color(0xFF221A13);
  static const Color bg3 = Color(0xFF2A1F16);

  // ── strokes ───────────────────────────────────────────────────
  static const Color stroke = Color(0x24C9A875); // rgba(201,168,117,0.14)
  static const Color strokeSoft = Color(0x14FFF7E8); // rgba(255,247,232,0.08)
  static const Color strokeStrong = Color(0x4DC9A875); // rgba(201,168,117,0.30)

  // ── gold scale ────────────────────────────────────────────────
  static const Color gold = Color(0xFFC9A875);
  static const Color goldLight = Color(0xFFE6CB95);
  static const Color goldBright = Color(0xFFF5DDA3);
  static const Color goldDeep = Color(0xFF8A6D40);
  static const Color goldShadow = Color(0xFF4D3A1F);

  // ── text ──────────────────────────────────────────────────────
  static const Color text = Color(0xFFF6EDDC);
  static const Color textMute = Color(0xFFB8A78A);
  static const Color textSoft = Color(0x8CF6EDDC); // 0.55
  static const Color textFaint = Color(0x52F6EDDC); // 0.32

  // ── signals ───────────────────────────────────────────────────
  static const Color on = Color(0xFF6BD49A);
  static const Color onGlow = Color(0x666BD49A); // 0.40
  static const Color warn = Color(0xFFF5B946);
  static const Color danger = Color(0xFFE26A5E);

  // ── gradients ─────────────────────────────────────────────────
  static const LinearGradient gradGold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF5DDA3), Color(0xFFC9A875), Color(0xFF8A6D40)],
    stops: [0.0, 0.45, 1.0],
  );

  static const LinearGradient gradGoldSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE6CB95), Color(0xFFC9A875), Color(0xFFA0834F)],
    stops: [0.0, 0.6, 1.0],
  );

  static const RadialGradient gradBg = RadialGradient(
    center: Alignment(0, -1), // 50% 0%
    radius: 1.2,
    colors: [Color(0xFF2A1C10), Color(0xFF14100C), Color(0xFF0C0907)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient gradCard = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0FC9A875), Color(0x05C9A875)], // 0.06 → 0.02
  );

  static const LinearGradient gradPyrite = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF5DDA3),
      Color(0xFFC9A875),
      Color(0xFF8A6D40),
      Color(0xFF4D3A1F),
    ],
    stops: [0.0, 0.4, 0.75, 1.0],
  );

  static const LinearGradient gradTextGold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF5DDA3), Color(0xFFC9A875), Color(0xFFA88557)],
    stops: [0.0, 0.6, 1.0],
  );

  // ── radii ─────────────────────────────────────────────────────
  static const double rXs = 6;
  static const double rSm = 10;
  static const double rMd = 16;
  static const double rLg = 22;
  static const double rXl = 28;
  static const double rPill = 999;

  // ── spacing ───────────────────────────────────────────────────
  static const double sp1 = 4;
  static const double sp2 = 8;
  static const double sp3 = 12;
  static const double sp4 = 16;
  static const double sp5 = 20;
  static const double sp6 = 24;
  static const double sp7 = 32;
  static const double sp8 = 40;

  // ── shadows ───────────────────────────────────────────────────
  static const List<BoxShadow> shadowCard = [
    BoxShadow(
      color: Color(0x8C000000), // rgba(0,0,0,0.55)
      blurRadius: 32,
      offset: Offset(0, 12),
      spreadRadius: -16,
    ),
    BoxShadow(
      color: Color(0x4D000000), // rgba(0,0,0,0.30)
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowGold = [
    BoxShadow(
      color: Color(0x8CC9A875), // rgba(201,168,117,0.55)
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -10,
    ),
    BoxShadow(
      color: Color(0x33C9A875), // rgba(201,168,117,0.20)
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowGlow = [
    BoxShadow(
      color: Color(0x2EF5DDA3), // rgba(245,221,163,0.18)
      blurRadius: 60,
    ),
    BoxShadow(
      color: Color(0x1AC9A875), // rgba(201,168,117,0.10)
      blurRadius: 120,
    ),
  ];

  // ── fonts ─────────────────────────────────────────────────────
  static const String fontSans = 'Manrope';
  static const String fontMono = 'JetBrainsMono';

  static TextStyle font({
    double? size,
    FontWeight? weight,
    Color? color,
    double? letterSpacing,
    double? height,
    bool mono = false,
  }) {
    return TextStyle(
      fontFamily: mono ? fontMono : fontSans,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

/// Legacy alias-класс. Старые экраны (settings_screen) на него ссылаются.
/// Значения переведены на новую warm-pyrite палитру — старый код визуально
/// тоже подхватит новый бренд без переписывания.
class PyritaColors {
  PyritaColors._();

  // Brand: warm gold. Pyrite-500 = signature.
  static const Color pyrite50 = Color(0xFFFCF5E5);
  static const Color pyrite100 = Color(0xFFF5DDA3);
  static const Color pyrite200 = Color(0xFFE6CB95);
  static const Color pyrite300 = Color(0xFFD5B988);
  static const Color pyrite400 = Color(0xFFC9A875);
  static const Color pyrite500 = Color(0xFFC9A875);
  static const Color pyrite600 = Color(0xFFA88557);
  static const Color pyrite700 = Color(0xFF8A6D40);
  static const Color pyrite800 = Color(0xFF5D4628);
  static const Color pyrite900 = Color(0xFF4D3A1F);

  // Ember — accent.
  static const Color ember = Color(0xFFFFAA32);
  static const Color emberSoft = Color(0xFFFFC04A);
  static const Color emberHot = Color(0xFFE55A18);

  // Surfaces — warm near-black.
  static const Color obsidian = Color(0xFF14100C);
  static const Color obsidian2 = Color(0xFF1A1410);
  static const Color obsidian3 = Color(0xFF221A13);

  // Foreground / text.
  static const Color paper = Color(0xFFF6EDDC);
  static const Color paper70 = Color(0xB3F6EDDC);
  static const Color paper55 = Color(0x8CF6EDDC);
  static const Color paper40 = Color(0x52F6EDDC);

  // Semantic.
  static const Color success = Color(0xFF6BD49A);
  static const Color destructive = Color(0xFFE26A5E);

  // Borders.
  static const Color borderSubtle = Color(0x24C9A875);
  static const Color borderDefault = Color(0x4DC9A875);
}

/// Spacing — radii / gaps на 4-x grid. Legacy. Новые экраны используют
/// PyDS.spN / PyDS.rXxx напрямую.
class PyritaSpacing {
  PyritaSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xl2 = 32;
  static const double xl3 = 48;

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusFull = 9999;
}

TextTheme _buildTextTheme() {
  final base = ThemeData.dark().textTheme.apply(fontFamily: PyDS.fontSans);
  return base.copyWith(
    displayLarge: PyDS.font(
      size: 60,
      weight: FontWeight.w800,
      letterSpacing: -1.0,
      height: 1.05,
      color: PyDS.text,
    ),
    displayMedium: PyDS.font(
      size: 44,
      weight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.06,
      color: PyDS.text,
    ),
    headlineLarge: PyDS.font(
      size: 32,
      weight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.1,
      color: PyDS.text,
    ),
    headlineMedium: PyDS.font(
      size: 26,
      weight: FontWeight.w800,
      letterSpacing: -0.65,
      height: 1.15,
      color: PyDS.text,
    ),
    titleLarge: PyDS.font(
      size: 20,
      weight: FontWeight.w700,
      height: 1.2,
      color: PyDS.text,
    ),
    titleMedium: PyDS.font(
      size: 16,
      weight: FontWeight.w700,
      height: 1.25,
      color: PyDS.text,
    ),
    bodyLarge: PyDS.font(
      size: 15,
      weight: FontWeight.w500,
      height: 1.45,
      color: PyDS.text,
    ),
    bodyMedium: PyDS.font(
      size: 13,
      weight: FontWeight.w500,
      height: 1.45,
      color: PyDS.textSoft,
    ),
    bodySmall: PyDS.font(
      size: 12,
      weight: FontWeight.w500,
      height: 1.4,
      color: PyDS.textSoft,
    ),
    labelSmall: PyDS.font(
      size: 10,
      weight: FontWeight.w700,
      letterSpacing: 1.4,
      color: PyDS.textFaint,
    ),
  );
}

/// Главная Pyrita-тема. Dark-only.
ThemeData buildPyritaTheme() {
  final textTheme = _buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: PyDS.bg,
    primaryColor: PyDS.gold,
    colorScheme: const ColorScheme.dark(
      primary: PyDS.gold,
      onPrimary: Color(0xFF1A140A),
      secondary: PyDS.goldLight,
      onSecondary: Color(0xFF1A140A),
      surface: PyDS.bg1,
      onSurface: PyDS.text,
      error: PyDS.danger,
      onError: PyDS.text,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: PyDS.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PyDS.gold,
        foregroundColor: const Color(0xFF1A140A),
        textStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: PyDS.sp6,
          vertical: PyDS.sp4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PyDS.rPill),
        ),
        elevation: 0,
        minimumSize: const Size(0, 52),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PyDS.text,
        side: const BorderSide(color: PyDS.strokeStrong, width: 1),
        textStyle: textTheme.titleMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: PyDS.sp6,
          vertical: PyDS.sp4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PyDS.rPill),
        ),
        minimumSize: const Size(0, 52),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PyDS.bg1,
      hintStyle: textTheme.bodyMedium?.copyWith(color: PyDS.textFaint),
      labelStyle: textTheme.bodyMedium?.copyWith(color: PyDS.textMute),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PyDS.sp4,
        vertical: PyDS.sp4,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyDS.rMd),
        borderSide: const BorderSide(color: PyDS.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyDS.rMd),
        borderSide: const BorderSide(color: PyDS.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyDS.rMd),
        borderSide: const BorderSide(color: PyDS.gold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyDS.rMd),
        borderSide: const BorderSide(color: PyDS.danger),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: PyDS.strokeSoft,
      thickness: 1,
      space: 0,
    ),
  );
}
