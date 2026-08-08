/// ============================================================================
///  App theme — faithful port of the Vue app's visual identity
/// ============================================================================
///
///  Colors are lifted 1:1 from `:root` in src/assets/styles/main.css:
///  Emerald Green + Gold + Cream, Qomra as the primary Arabic face with Cairo
///  as fallback (same stack as the CSS `font-family`).
library;

import 'package:flutter/material.dart';

abstract final class BrandColors {
  /// وضع الواجهة الداكن — تضبطه themeModeProvider قبل بناء التطبيق.
  /// (رموز الألوان المتكيفة أدناه getters تقرأه، فتتبدل الشاشات كلها.)
  static bool darkMode = false;

  // ── Brand: Emerald Green + Gold + Cream (── main.css :root) ──
  static const brand900 = Color(0xFF0A3024); // --brand-900 / --navy
  static const brand700 = Color(0xFF114A38); // --brand-700
  static const brand600 = Color(0xFF15604A); // --brand-600 (theme-color)
  static const brand = Color(0xFF1B5E47); // --brand

  static const gold = Color(0xFFC9A24B); // --gold
  static const goldLight = Color(0xFFE4CA85); // --gold-l
  static const goldDark = Color(0xFF9C7A2E); // --gold-d

  // ── أزواج الوضعين (من main.css: الفاتح سطر 20-21 والداكن 802-803) ──
  static const paperLight = Color(0xFFF6F2E8);
  static const paperDark = Color(0xFF0A3024);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF123F30); // --navy-card
  static const surface2Light = Color(0xFFFBF8F0);
  static const surface2Dark = Color(0xFF0E3D2E);
  static const inkLight = Color(0xFF0F2A20);
  static const inkDark = Color(0xFFEAF3EE);

  static Color get paper => darkMode ? paperDark : paperLight;
  static Color get surface => darkMode ? surfaceDark : surfaceLight;
  static Color get surface2 => darkMode ? surface2Dark : surface2Light;
  static Color get ink => darkMode ? inkDark : inkLight;
  static Color get inkInverse => darkMode ? inkLight : inkDark;

  // ── رموز نصية متكيفة (بدائل Colors.black* المصلدة) ──
  // م42 — تباين مرجع الأصل: النص الثانوي في Vue بعتامة 72% من الحبر
  // (rgba(15,42,32,.72)) وplaceholder بعتامة 50% — اللوحة القديمة
  // (54/45/38%) كانت أفتح فتُقرأ بإجهاد. الحبر ink = #0F2A20.
  static Color get mut => darkMode
      ? const Color(0xC9EAF3EE)
      : const Color.fromRGBO(15, 42, 32, .72); // ثانوي (مرجع Vue)
  static Color get mut2 => darkMode
      ? const Color(0xA8EAF3EE)
      : const Color.fromRGBO(15, 42, 32, .62); // وسوم/حواشٍ
  static Color get faint => darkMode
      ? const Color(0x80EAF3EE)
      : const Color.fromRGBO(15, 42, 32, .50); // placeholder-grade
  static Color get faint2 =>
      darkMode ? const Color(0x4DEAF3EE) : Colors.black26;
  static Color get line =>
      darkMode ? const Color(0x26EAF3EE) : Colors.black12;
  static Color get strong =>
      darkMode ? const Color(0xF2EAF3EE) : Colors.black87;

  /// أخضر العلامة فاتحاً قليلاً في الداكن (تباين أفضل على الأسطح الداكنة).
  static Color get brandText =>
      darkMode ? const Color(0xFF7FC8A9) : brand700;
  static Color get brandIcon =>
      darkMode ? const Color(0xFF5FB08D) : brand600;

  static const green = Color(0xFF1E7A52); // --green
  static const red = Color(0xFFC0392B); // --red
  static const orange = Color(0xFFB8860B); // --orange

  /// --brand-g: linear-gradient(160deg, #15604A, #0A3024)
  static const brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomLeft,
    colors: [brand600, brand900],
  );
}

ThemeData buildAppTheme({bool dark = false}) {
  final paper = dark ? BrandColors.paperDark : BrandColors.paperLight;
  final surface = dark ? BrandColors.surfaceDark : BrandColors.surfaceLight;
  final ink = dark ? BrandColors.inkDark : BrandColors.inkLight;

  final scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.brand600,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: dark ? const Color(0xFF5FB08D) : BrandColors.brand600,
    onPrimary: dark ? BrandColors.brand900 : Colors.white,
    secondary: BrandColors.gold,
    onSecondary: BrandColors.brand900,
    surface: surface,
    onSurface: ink,
    error: BrandColors.red,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    fontFamily: 'Qomra',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Qomra',
      fontFamilyFallback: const ['Cairo'],
      bodyColor: ink,
      displayColor: ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BrandColors.brand900,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
    // التوأم الحرفي لـ .card في main.css: قطر 20، حد rgba(20,80,59,.1)،
    // وظل sh-1 ناعم (0 2px 8px rgba(10,48,36,.06)) بدل ظل Material الحاد.
    cardTheme: CardThemeData(
      color: surface,
      elevation: 1,
      shadowColor: const Color.fromRGBO(10, 48, 36, .5),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: dark
              ? const Color.fromRGBO(255, 255, 255, .08)
              : const Color.fromRGBO(20, 80, 59, .1),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: (dark ? Colors.white : BrandColors.brand900)
          .withValues(alpha: .08),
    ),
    dialogTheme: DialogThemeData(backgroundColor: surface),
  );
}
