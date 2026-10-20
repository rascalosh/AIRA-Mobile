import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AIRA design tokens, transcribed from the Figma "Foundations" frame.
///
/// Two themes share one set of semantic names: **Standard** (light, indigo)
/// for Home, Studies and detail screens, and **Reading mode** (dark) for the
/// MRI viewer and result screens. Widgets read colours through
/// `context.aira` and must not contain raw hex values.
class Indigo {
  Indigo._();
  static const c50 = Color(0xFFEEF0FB);
  static const c100 = Color(0xFFDDE1F6);
  static const c300 = Color(0xFF8C98E0);
  static const c500 = Color(0xFF4B5BD6);
  static const c600 = Color(0xFF3A47B0);
  static const c700 = Color(0xFF2F3A8F);
  static const c800 = Color(0xFF262F78);
  static const c900 = Color(0xFF1C2360);
}

class Grays {
  Grays._();
  static const c50 = Color(0xFFF6F7FA);
  static const c100 = Color(0xFFEEF0F4);
  static const c200 = Color(0xFFE3E6ED);
  static const c400 = Color(0xFFA3A9B8);
  static const c600 = Color(0xFF5E6475);
  static const c900 = Color(0xFF1A1D26);
}

/// 4pt spacing grid.
class AppSpacing {
  AppSpacing._();
  static const xs = 4.0; // space-1: icon-text gap in chips
  static const sm = 8.0; // space-2: gap between chips
  static const s3 = 12.0; // space-3: tight card gap
  static const md = 16.0; // space-4: card padding, card gap
  static const s5 = 20.0; // space-5: horizontal screen padding
  static const lg = 24.0; // space-6: between sections
  static const xl = 32.0; // space-8: empty-state padding
  static const s10 = 40.0; // space-10: empty-state illustration
  static const xxl = 48.0;

  static const screenH = s5;
}

class AppRadius {
  AppRadius._();
  static const sm = 8.0; // chips, badges
  static const md = 12.0; // inputs, buttons
  static const lg = 16.0; // cards
  static const xl = 20.0; // hero card
  static const pill = 999.0; // search pill
}

/// Semantic colour tokens, one instance per theme.
@immutable
class AiraColors extends ThemeExtension<AiraColors> {
  const AiraColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.textTitle,
    required this.textPrimary,
    required this.textSecondary,
    required this.focus,
    required this.successFg,
    required this.successBg,
    required this.infoFg,
    required this.infoBg,
    required this.warningFg,
    required this.warningBg,
    required this.dangerFg,
    required this.dangerBg,
    required this.neutralFg,
    required this.neutralBg,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color primary;
  final Color primaryPressed;
  final Color onPrimary;
  final Color textTitle;
  final Color textPrimary;
  final Color textSecondary;
  final Color focus;
  final Color successFg;
  final Color successBg;
  final Color infoFg;
  final Color infoBg;
  final Color warningFg;
  final Color warningBg;
  final Color dangerFg;
  final Color dangerBg;
  final Color neutralFg;
  final Color neutralBg;

  static const standard = AiraColors(
    background: Grays.c50,
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Grays.c100,
    border: Grays.c200,
    primary: Indigo.c700,
    primaryPressed: Indigo.c600,
    onPrimary: Color(0xFFFFFFFF),
    textTitle: Indigo.c900,
    textPrimary: Grays.c900,
    textSecondary: Grays.c600,
    focus: Indigo.c500,
    successFg: Color(0xFF1E7F52),
    successBg: Color(0xFFE3F5EC),
    infoFg: Indigo.c700,
    infoBg: Indigo.c50,
    warningFg: Color(0xFF9A5B00),
    warningBg: Color(0xFFFFF1D6),
    dangerFg: Color(0xFFC2303A),
    dangerBg: Color(0xFFFDE8E9),
    neutralFg: Grays.c600,
    neutralBg: Grays.c100,
  );

  static const reading = AiraColors(
    background: Color(0xFF07080C),
    surface: Color(0xFF12141D),
    surfaceMuted: Color(0xFF1B1E2A),
    border: Color(0xFF2A2E3D),
    primary: Color(0xFF8C98F2),
    primaryPressed: Color(0xFFA9B2F5),
    onPrimary: Color(0xFF07080C),
    textTitle: Color(0xFFE8EAF2),
    textPrimary: Color(0xFFE8EAF2),
    textSecondary: Color(0xFF9AA0B4),
    focus: Color(0xFF8C98F2),
    successFg: Color(0xFF5FD39B),
    successBg: Color(0xFF10291E),
    infoFg: Color(0xFF8C98F2),
    infoBg: Color(0xFF1C2140),
    warningFg: Color(0xFFF2B84B),
    warningBg: Color(0xFF2E2210),
    dangerFg: Color(0xFFF2777F),
    dangerBg: Color(0xFF33161A),
    neutralFg: Color(0xFF9AA0B4),
    neutralBg: Color(0xFF1B1E2A),
  );

  /// The one gradient in the system: HeroCard, Standard theme only.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Indigo.c700, Indigo.c900],
  );

  @override
  AiraColors copyWith() => this;

  @override
  AiraColors lerp(ThemeExtension<AiraColors>? other, double t) {
    if (other is! AiraColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AiraColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      border: l(border, other.border),
      primary: l(primary, other.primary),
      primaryPressed: l(primaryPressed, other.primaryPressed),
      onPrimary: l(onPrimary, other.onPrimary),
      textTitle: l(textTitle, other.textTitle),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      focus: l(focus, other.focus),
      successFg: l(successFg, other.successFg),
      successBg: l(successBg, other.successBg),
      infoFg: l(infoFg, other.infoFg),
      infoBg: l(infoBg, other.infoBg),
      warningFg: l(warningFg, other.warningFg),
      warningBg: l(warningBg, other.warningBg),
      dangerFg: l(dangerFg, other.dangerFg),
      dangerBg: l(dangerBg, other.dangerBg),
      neutralFg: l(neutralFg, other.neutralFg),
      neutralBg: l(neutralBg, other.neutralBg),
    );
  }
}

/// Segmentation label colours. Fill at 40% alpha with a 1.5px outline; used
/// only for overlays and their legend.
class SegColors {
  SegColors._();
  static const cyan = Color(0xFF22D3EE);
  static const amber = Color(0xFFF59E0B);
  static const magenta = Color(0xFFE879F9);
  static const lime = Color(0xFFA3E635);
  static const all = [cyan, amber, magenta, lime];
  static const fillAlpha = 0.4;
  static const outlineWidth = 1.5;
}

extension AiraTheme on BuildContext {
  AiraColors get aira =>
      Theme.of(this).extension<AiraColors>() ?? AiraColors.standard;
}

double lerpSpacing(double a, double b, double t) => lerpDouble(a, b, t)!;

class AppTheme {
  AppTheme._();

  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _s(
    AiraColors c,
    double size,
    double height,
    FontWeight weight, {
    Color? color,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color ?? c.textPrimary,
      fontFeatures: _tabular,
    );
  }

  static TextTheme _textTheme(AiraColors c) {
    return TextTheme(
      displayLarge: _s(c, 32, 40, FontWeight.w600, color: c.textTitle),
      displayMedium: _s(c, 32, 40, FontWeight.w600, color: c.textTitle),
      displaySmall: _s(c, 32, 40, FontWeight.w600, color: c.textTitle),
      headlineLarge: _s(c, 24, 32, FontWeight.w600, color: c.textTitle),
      headlineMedium: _s(c, 20, 28, FontWeight.w600, color: c.textTitle),
      headlineSmall: _s(c, 17, 24, FontWeight.w600, color: c.textTitle),
      titleLarge: _s(c, 20, 28, FontWeight.w500, color: c.textTitle),
      titleMedium: _s(c, 17, 24, FontWeight.w500),
      titleSmall: _s(c, 14, 20, FontWeight.w500),
      bodyLarge: _s(c, 16, 24, FontWeight.w400),
      bodyMedium: _s(c, 14, 20, FontWeight.w400),
      bodySmall: _s(c, 12, 16, FontWeight.w400, color: c.textSecondary),
      labelLarge: _s(c, 14, 20, FontWeight.w500),
      labelMedium: _s(c, 12, 16, FontWeight.w500, color: c.textSecondary),
      labelSmall: _s(c, 11, 16, FontWeight.w500, color: c.textSecondary),
    );
  }

  static ThemeData? _standard;
  static ThemeData? _reading;

  static ThemeData standard() =>
      _standard ??= _build(AiraColors.standard, Brightness.light);

  /// Reading mode: dark chrome for the viewer and result screens.
  static ThemeData reading() =>
      _reading ??= _build(AiraColors.reading, Brightness.dark);

  static ThemeData _build(AiraColors c, Brightness brightness) {
    final textTheme = _textTheme(c);
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.primary,
      onSecondary: c.onPrimary,
      error: c.dangerFg,
      onError: c.onPrimary,
      surface: c.background,
      onSurface: c.textPrimary,
      outline: c.border,
      outlineVariant: c.border,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    const buttonSize = Size.fromHeight(48);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      textTheme: textTheme,
      extensions: [c],
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textTitle,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 56,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.textTitle),
      ),
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: 1,
        space: AppSpacing.md,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.surfaceMuted,
          disabledForegroundColor: c.textSecondary,
          minimumSize: buttonSize,
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          disabledForegroundColor: c.textSecondary,
          backgroundColor: c.surface,
          side: BorderSide(color: c.border),
          minimumSize: buttonSize,
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(48, 48),
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textTitle,
          disabledForegroundColor: c.textSecondary.withValues(alpha: 0.5),
          minimumSize: const Size(48, 48),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: brightness == Brightness.dark
            ? c.border
            : Indigo.c100,
        thumbColor: c.primary,
        overlayColor: c.primary.withValues(alpha: 0.14),
        valueIndicatorColor: c.primary,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: c.onPrimary,
        ),
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(
          c.onPrimary == Colors.white ? Colors.white : c.textTitle,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary
              : c.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.all(c.border),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.infoBg,
        linearMinHeight: 4,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: c.border,
        indicatorColor: c.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: c.textTitle,
        unselectedLabelColor: c.textSecondary,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: textTheme.bodyLarge?.copyWith(color: c.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c.focus, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s3,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.textTitle,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.background),
        actionTextColor: c.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
