import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color _brandRed = Color(0xFFB1181A);
  static const Color _brandRedDark = Color(0xFF8F1013);
  static const Color _brandGold = Color(0xFFD9A62A);
  static const Color _brandInk = Color(0xFF1B1D22);
  static const Color _brandPaper = Color(0xFFF5F6F8);

  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: _brandRed,
      brightness: Brightness.light,
    );

    final textTheme = GoogleFonts.notoSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: baseScheme.copyWith(
        primary: _brandRed,
        onPrimary: Colors.white,
        secondary: _brandRedDark,
        onSecondary: Colors.white,
        tertiary: _brandGold,
        onTertiary: _brandInk,
        surface: Colors.white,
        surfaceContainerHighest: const Color(0xFFE7E9EF),
        onSurface: _brandInk,
      ),
      scaffoldBackgroundColor: _brandPaper,
      textTheme: textTheme.copyWith(
        headlineLarge: GoogleFonts.oswald(
          fontSize: 38,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: _brandInk,
        ),
        headlineMedium: GoogleFonts.oswald(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: _brandInk,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: _brandInk,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: _brandInk,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _brandInk,
        titleTextStyle: GoogleFonts.oswald(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: _brandInk,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDCE1EA)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF9FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCFD5E3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCFD5E3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brandRed, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandRed,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brandInk,
          side: const BorderSide(color: Color(0xFFBCC3D3)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brandRedDark,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        iconColor: Color(0xFF3B465B),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        thickness: 1,
        color: Color(0xFFE1E5EE),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
