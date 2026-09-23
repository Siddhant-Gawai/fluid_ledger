import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary palette
  static const Color primary = Color(0xFF3F51B5);
  static const Color primaryContainer = Color(0xFF24389C);
  static const Color onPrimary = Color(0xFFffffff);
  static const Color onPrimaryContainer = Color(0xFFcacfff);
  static const Color primaryFixed = Color(0xFFdee0ff);
  static const Color primaryFixedDim = Color(0xFFbac3ff);

  // Secondary palette
  static const Color secondary = Color(0xFF006a6a);
  static const Color secondaryContainer = Color(0xFF90efef);
  static const Color onSecondary = Color(0xFFffffff);
  static const Color onSecondaryContainer = Color(0xFF006e6e);
  static const Color secondaryFixed = Color(0xFF93f2f2);
  static const Color secondaryFixedDim = Color(0xFF76d6d5);

  // Tertiary palette
  static const Color tertiary = Color(0xFF313e7e);
  static const Color tertiaryContainer = Color(0xFF495697);
  static const Color tertiaryFixed = Color(0xFFdee1ff);

  // Surface palette
  static const Color surface = Color(0xFFf8f9fe);
  static const Color surfaceDim = Color(0xFFd8dadf);
  static const Color surfaceBright = Color(0xFFf8f9fe);
  static const Color surfaceContainerLowest = Color(0xFFffffff);
  static const Color surfaceContainerLow = Color(0xFFf2f3f8);
  static const Color surfaceContainer = Color(0xFFeceef3);
  static const Color surfaceContainerHigh = Color(0xFFe7e8ed);
  static const Color surfaceContainerHighest = Color(0xFFe1e2e7);
  static const Color surfaceVariant = Color(0xFFe1e2e7);

  // On colors
  static const Color onSurface = Color(0xFF191c1f);
  static const Color onSurfaceVariant = Color(0xFF454652);
  static const Color outline = Color(0xFF757684);
  static const Color outlineVariant = Color(0xFFc5c5d4);

  // Error
  static const Color error = Color(0xFFba1a1a);
  static const Color errorContainer = Color(0xFFffdad6);
  static const Color onError = Color(0xFFffffff);
  static const Color onErrorContainer = Color(0xFF93000a);

  // Inverse
  static const Color inverseSurface = Color(0xFF2e3134);
  static const Color inverseOnSurface = Color(0xFFeff0f5);
  static const Color inversePrimary = Color(0xFFbac3ff);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        primaryContainer: primaryContainer,
        onPrimary: onPrimary,
        onPrimaryContainer: onPrimaryContainer,
        primaryFixed: primaryFixed,
        primaryFixedDim: primaryFixedDim,
        secondary: secondary,
        secondaryContainer: secondaryContainer,
        onSecondary: onSecondary,
        onSecondaryContainer: onSecondaryContainer,
        secondaryFixed: secondaryFixed,
        secondaryFixedDim: secondaryFixedDim,
        tertiary: tertiary,
        tertiaryContainer: tertiaryContainer,
        tertiaryFixed: tertiaryFixed,
        surface: surface,
        surfaceDim: surfaceDim,
        surfaceBright: surfaceBright,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
        error: error,
        errorContainer: errorContainer,
        onError: onError,
        onErrorContainer: onErrorContainer,
        inverseSurface: inverseSurface,
        inversePrimary: inversePrimary,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: TextTheme(
        headlineLarge: GoogleFonts.manrope(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: onSurface,
          height: 1.2,
        ),
        headlineMedium: GoogleFonts.manrope(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: onSurface,
          height: 1.3,
        ),
        headlineSmall: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        titleLarge: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        titleMedium: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        titleSmall: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: onSurface,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: onSurfaceVariant,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: onSurfaceVariant,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: onSurfaceVariant,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: onSurface),
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outlineVariant.withValues(alpha: 0.15)),
        ),
        margin: EdgeInsets.zero,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: inverseOnSurface,
        ),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}
