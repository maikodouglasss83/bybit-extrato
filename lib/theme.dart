import 'package:flutter/material.dart';

/// Paleta do app. Um tom escuro azulado com acento verde-água, no espírito
/// dos apps de finanças que serviram de referência.
class AppColors {
  static const accent = Color(0xFF22D3A6);
  static const accentSoft = Color(0xFF14B88A);
  static const positive = Color(0xFF22C55E);
  static const negative = Color(0xFFF4436B);
  static const warning = Color(0xFFF5A524);

  // Escuro
  static const darkBg = Color(0xFF0A0E14);
  static const darkSurface = Color(0xFF121A23);
  static const darkSurfaceAlt = Color(0xFF1A2430);
  static const darkBorder = Color(0xFF243040);
  static const darkText = Color(0xFFE9EFF6);
  static const darkMuted = Color(0xFF8798AB);

  // Claro
  static const lightBg = Color(0xFFF4F6FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFEEF2F7);
  static const lightBorder = Color(0xFFDDE4EC);
  static const lightText = Color(0xFF0E1720);
  static const lightMuted = Color(0xFF64748B);
}

/// Cores que dependem do brilho do tema, acessíveis via `context.tones`.
class AppTones extends ThemeExtension<AppTones> {
  const AppTones({
    required this.surfaceAlt,
    required this.border,
    required this.muted,
    required this.positive,
    required this.negative,
  });

  final Color surfaceAlt;
  final Color border;
  final Color muted;
  final Color positive;
  final Color negative;

  @override
  AppTones copyWith({
    Color? surfaceAlt,
    Color? border,
    Color? muted,
    Color? positive,
    Color? negative,
  }) =>
      AppTones(
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        muted: muted ?? this.muted,
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
      );

  @override
  AppTones lerp(ThemeExtension<AppTones>? other, double t) {
    if (other is! AppTones) return this;
    return AppTones(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
    );
  }
}

extension ToneAccess on BuildContext {
  AppTones get tones => Theme.of(this).extension<AppTones>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final bg = dark ? AppColors.darkBg : AppColors.lightBg;
  final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
  final surfaceAlt = dark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
  final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
  final text = dark ? AppColors.darkText : AppColors.lightText;
  final muted = dark ? AppColors.darkMuted : AppColors.lightMuted;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: AppColors.accent,
    onPrimary: const Color(0xFF04211A),
    secondary: AppColors.accentSoft,
    onSecondary: Colors.white,
    error: AppColors.negative,
    onError: Colors.white,
    surface: surface,
    onSurface: text,
    surfaceContainerHighest: surfaceAlt,
    outline: border,
  );

  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    dividerColor: border,
    extensions: [
      AppTones(
        surfaceAlt: surfaceAlt,
        border: border,
        muted: muted,
        positive: AppColors.positive,
        negative: AppColors.negative,
      ),
    ],
    textTheme: base.textTheme
        .apply(bodyColor: text, displayColor: text, fontFamily: 'Roboto')
        .copyWith(
          displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.8),
          headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.3),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
          titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
          bodyMedium: TextStyle(fontSize: 14, color: text),
          bodySmall: TextStyle(fontSize: 12.5, color: muted),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.6),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: text),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      hintStyle: TextStyle(color: muted),
      labelStyle: TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF04211A),
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.16),
      surfaceTintColor: Colors.transparent,
      height: 66,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? text : muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 23,
          color: s.contains(WidgetState.selected) ? AppColors.accent : muted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.16),
      selectedIconTheme: const IconThemeData(color: AppColors.accent, size: 24),
      unselectedIconTheme: IconThemeData(color: muted, size: 24),
      selectedLabelTextStyle: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelTextStyle: TextStyle(color: muted, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceAlt,
      contentTextStyle: TextStyle(color: text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
  );
}
