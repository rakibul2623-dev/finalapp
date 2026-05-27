export 'package:hajj_wallet/utils/color_compat.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFF168041);
  static const Color primaryForeground = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFF2B928);
  static const Color background = Color(0xFFEEF4EF);
  static const Color surface = Color(0xFFFCFEFC);
  static const Color foreground = Color(0xFF152821);
  static const Color mutedForeground = Color(0xFF5C6B62);
  static const Color border = Color(0xFFC2D4C7);
  static const Color inputBackground = Color(0xFFF0F4F1);
  static const Color success = Color(0xFF168041);
  static const Color destructive = Color(0xFFDD3838);
  static const Color darkTeal = Color(0xFF0F4C3A);
  static const Color deepTeal = Color(0xFF063D28);
  static const Color primaryGlow = Color(0xFF22B85F);
  
  // Tier Colors
  static const Color silverTier = Color(0xFF9CA3AF);
  static const Color goldTier = Color(0xFFF0B520);
  static const Color platinumTier = Color(0xFFE5E7EB);

  // Tier badge palette (for chips/badges)
  static const Color tierSilverBg = Color(0xFFF3F4F6);
  static const Color tierSilverText = Color(0xFF6B7280);
  static const Color tierGoldBg = Color(0xFFFEF9C3);
  static const Color tierGoldText = Color(0xFFD97706);
  static const Color tierPlatinumBg = Color(0xFFF1F5F9);
  static const Color tierPlatinumText = Color(0xFF475569);
  static const Color tierPlatinumBorder = Color(0xFFCBD5E1);
}

class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double pill = 999.0;
}

TextTheme _buildTextTheme() {
  return TextTheme(
    displayLarge: GoogleFonts.inter(
      fontSize: 48.0,
      fontWeight: FontWeight.w800,
      color: AppColors.foreground,
    ),
    displayMedium: GoogleFonts.inter(
      fontSize: 36.0,
      fontWeight: FontWeight.w700,
      color: AppColors.foreground,
    ),
    headlineLarge: GoogleFonts.inter(
      fontSize: 28.0,
      fontWeight: FontWeight.w600,
      color: AppColors.foreground,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: 24.0,
      fontWeight: FontWeight.w600,
      color: AppColors.foreground,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: 20.0,
      fontWeight: FontWeight.w600,
      color: AppColors.foreground,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 18.0,
      fontWeight: FontWeight.w400,
      color: AppColors.foreground,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 16.0,
      fontWeight: FontWeight.w400,
      color: AppColors.foreground,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      color: AppColors.mutedForeground,
    ),
    labelSmall: GoogleFonts.inter(
      fontSize: 12.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5, // tracking-wider
      color: AppColors.foreground,
    ),
  );
}

ThemeData get appTheme => ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.primaryForeground,
    secondary: AppColors.accent,
    onSecondary: AppColors.foreground,
    surface: AppColors.surface,
    onSurface: AppColors.foreground,
    error: AppColors.destructive,
    onError: AppColors.primaryForeground,
    outline: AppColors.border,
  ),
  textTheme: _buildTextTheme(),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: AppColors.foreground,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: const BorderSide(color: AppColors.border, width: 1),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.primaryForeground,
      elevation: 0,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      textStyle: GoogleFonts.inter(
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.primary, width: 1.5),
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      textStyle: GoogleFonts.inter(
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle: GoogleFonts.inter(
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.inputBackground,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    hintStyle: GoogleFonts.inter(
      color: AppColors.mutedForeground,
      fontSize: 16,
      fontWeight: FontWeight.w400,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.border, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: const BorderSide(color: AppColors.destructive, width: 1),
    ),
  ),
);

// Fallback for Dreamflow's expected lightTheme/darkTheme exports
ThemeData get lightTheme => appTheme;
ThemeData get darkTheme => appTheme; // Using same theme for now as specs only provided one set

extension TextStyleExtensions on TextStyle {
  TextStyle get bold => copyWith(fontWeight: FontWeight.bold);
  TextStyle get semiBold => copyWith(fontWeight: FontWeight.w600);
  TextStyle get medium => copyWith(fontWeight: FontWeight.w500);
  TextStyle get normal => copyWith(fontWeight: FontWeight.w400);
  TextStyle withColor(Color color) => copyWith(color: color);
}
