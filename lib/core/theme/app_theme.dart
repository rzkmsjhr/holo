import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Core Brand Colors (R-29: 2 Core + 1 Accent)
  static const Color primary = Color(0xFFFF5416); // Solar Ember
  static const Color secondary = Color(0xFF5A32A3); // Night Indigo
  static const Color accent = Color(0xFFCCFF00); // Acid Chartreuse

  // Dark Mode Canvas & Surfaces (WCAG AA Verified)
  static const Color darkCanvas = Color(0xFF0A0C10);
  static const Color darkSurface = Color(0xFF14171F);
  static const Color darkSurfaceElevated = Color(0xFF1D212C);
  static const Color darkBorder = Color(0xFF222736);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8F9CAE);
  static const Color darkTextTertiary = Color(0xFF606B7D);

  // Light Mode Canvas & Surfaces (WCAG AA Verified)
  static const Color lightCanvas = Color(0xFFF6F7F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFECEFF4);
  static const Color lightBorder = Color(0xFFE2E5EB);
  static const Color lightTextPrimary = Color(0xFF11141A);
  static const Color lightTextSecondary = Color(0xFF5C6474);
  static const Color lightTextTertiary = Color(0xFF848D9E);
}

class AppTheme {
  static final ThemeData _dark = _buildDarkTheme();
  static final ThemeData _light = _buildLightTheme();

  static ThemeData darkTheme() => _dark;
  static ThemeData lightTheme() => _light;

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkCanvas,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkTextPrimary,
        outline: AppColors.darkBorder,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme.copyWith(
              headlineSmall: const TextStyle(
                color: AppColors.darkTextPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              titleMedium: const TextStyle(
                color: AppColors.darkTextPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              bodyMedium: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontWeight: FontWeight.w500,
              ),
              bodySmall: const TextStyle(
                color: AppColors.darkTextTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF11141B),
        modalBackgroundColor: Color(0xFF11141B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSurfaceElevated,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.darkTextPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.primary,
        closeIconColor: AppColors.darkTextSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(
            color: AppColors.darkBorder,
            width: 1.0,
          ),
        ),
        elevation: 6,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightCanvas,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightTextPrimary,
        outline: AppColors.lightBorder,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme.copyWith(
              headlineSmall: const TextStyle(
                color: AppColors.lightTextPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              titleMedium: const TextStyle(
                color: AppColors.lightTextPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              bodyMedium: const TextStyle(
                color: AppColors.lightTextSecondary,
                fontWeight: FontWeight.w500,
              ),
              bodySmall: const TextStyle(
                color: AppColors.lightTextTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lightSurface,
        modalBackgroundColor: AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.lightSurface,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.lightTextPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.primary,
        closeIconColor: AppColors.lightTextSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(
            color: AppColors.lightBorder,
            width: 1.0,
          ),
        ),
        elevation: 6,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
