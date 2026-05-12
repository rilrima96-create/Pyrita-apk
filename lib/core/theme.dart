import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pyrita design tokens. Copy-paste из `pyrita-web/src/styles/colors_and_type.css`
/// чтобы web и мобайл выглядели единообразно. При изменении в одном месте —
/// менять в обоих (TODO: shared design-tokens package при росте проекта).
class PyritaColors {
  PyritaColors._();

  // Brand: brushed honey-amber. Pyrite-500 — signature.
  static const Color pyrite50 = Color(0xFFF8EBC7);
  static const Color pyrite100 = Color(0xFFF2D58A);
  static const Color pyrite200 = Color(0xFFE8BE63);
  static const Color pyrite300 = Color(0xFFD8A044);
  static const Color pyrite400 = Color(0xFFC99A3F);
  static const Color pyrite500 = Color(0xFFB6822E);
  static const Color pyrite600 = Color(0xFF965E1B);
  static const Color pyrite700 = Color(0xFF7A5519);
  static const Color pyrite800 = Color(0xFF4F3811);
  static const Color pyrite900 = Color(0xFF2B1E08);

  // Ember — live-state colour (connection active, alerts).
  static const Color ember = Color(0xFFE8643A);
  static const Color emberSoft = Color(0xFFF08A3A);
  static const Color emberHot = Color(0xFFC44E1B);

  // Surfaces — warm near-black.
  static const Color obsidian = Color(0xFF0E0F12);
  static const Color obsidian2 = Color(0xFF16181C);
  static const Color obsidian3 = Color(0xFF1F2229);

  // Foreground / text.
  static const Color paper = Color(0xFFF4F1EA);
  static const Color paper70 = Color(0xB3F4F1EA); // 70% alpha
  static const Color paper55 = Color(0x8CF4F1EA); // 55% alpha
  static const Color paper40 = Color(0x66F4F1EA); // 40% alpha

  // Semantic.
  static const Color success = Color(0xFF4ADE80); // emerald-400
  static const Color destructive = Color(0xFFEF4444);

  // Borders.
  static const Color borderSubtle = Color(0x14FFFFFF); // white/8 = ~0.08
  static const Color borderDefault = Color(0x29FFFFFF); // white/16 = ~0.16
}

/// Spacing — radii / gaps на 4-x grid. Соответствует Tailwind-токенам.
class PyritaSpacing {
  PyritaSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xl2 = 32;
  static const double xl3 = 48;

  // Radii.
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusFull = 9999;
}

/// Pyrita TextTheme. Manrope для UI + JetBrains Mono для monospace
/// (microcopy, копируемые URL). Загружается через google_fonts.
///
/// При offline-first redesign — bundle .ttf files в assets/fonts/ и заменить
/// `GoogleFonts.manrope` на `TextStyle(fontFamily: "Manrope")`.
TextTheme _buildTextTheme() {
  final base = ThemeData.dark().textTheme;
  return GoogleFonts.manropeTextTheme(base).copyWith(
    displayLarge: GoogleFonts.manrope(
      fontSize: 60,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
      height: 1.05,
      color: PyritaColors.paper,
    ),
    displayMedium: GoogleFonts.manrope(
      fontSize: 44,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.06,
      color: PyritaColors.paper,
    ),
    headlineLarge: GoogleFonts.manrope(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.1,
      color: PyritaColors.paper,
    ),
    headlineMedium: GoogleFonts.manrope(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.15,
      color: PyritaColors.paper,
    ),
    titleLarge: GoogleFonts.manrope(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: PyritaColors.paper,
    ),
    titleMedium: GoogleFonts.manrope(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: PyritaColors.paper,
    ),
    bodyLarge: GoogleFonts.manrope(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: PyritaColors.paper,
    ),
    bodyMedium: GoogleFonts.manrope(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.55,
      color: PyritaColors.paper70,
    ),
    bodySmall: GoogleFonts.manrope(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: PyritaColors.paper55,
    ),
    labelSmall: GoogleFonts.manrope(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      color: PyritaColors.paper55,
    ),
  );
}

/// Главная Pyrita-тема. Dark-only — light-mode не предусмотрен (брендинг
/// решает что только dark).
ThemeData buildPyritaTheme() {
  final textTheme = _buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: PyritaColors.obsidian,
    primaryColor: PyritaColors.pyrite500,
    colorScheme: const ColorScheme.dark(
      primary: PyritaColors.pyrite500,
      onPrimary: PyritaColors.obsidian,
      secondary: PyritaColors.ember,
      onSecondary: PyritaColors.paper,
      surface: PyritaColors.obsidian2,
      onSurface: PyritaColors.paper,
      error: PyritaColors.destructive,
      onError: PyritaColors.paper,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: PyritaColors.obsidian,
      foregroundColor: PyritaColors.paper,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PyritaColors.pyrite500,
        foregroundColor: PyritaColors.obsidian,
        textStyle: textTheme.titleMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: PyritaSpacing.xl,
          vertical: PyritaSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PyritaSpacing.radiusFull),
        ),
        elevation: 0,
        minimumSize: const Size(0, 48),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PyritaColors.paper,
        side: const BorderSide(color: PyritaColors.borderDefault, width: 1),
        textStyle: textTheme.titleMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: PyritaSpacing.xl,
          vertical: PyritaSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PyritaSpacing.radiusFull),
        ),
        minimumSize: const Size(0, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PyritaColors.obsidian2,
      hintStyle: textTheme.bodyMedium?.copyWith(color: PyritaColors.paper40),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PyritaSpacing.lg,
        vertical: PyritaSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyritaSpacing.radiusMd),
        borderSide: const BorderSide(color: PyritaColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyritaSpacing.radiusMd),
        borderSide: const BorderSide(color: PyritaColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyritaSpacing.radiusMd),
        borderSide: const BorderSide(color: PyritaColors.pyrite500, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PyritaSpacing.radiusMd),
        borderSide: const BorderSide(color: PyritaColors.destructive),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: PyritaColors.borderSubtle,
      thickness: 1,
      space: 0,
    ),
  );
}
