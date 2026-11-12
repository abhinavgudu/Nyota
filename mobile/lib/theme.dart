import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Nyota brand colours — taken from the logo (deep maroon + gold + cream).
class NyotaColors {
  /// Primary brand maroon (the "Nyota" wordmark / crown).
  static const royalPurple = Color(0xFF7B1119);
  /// Deeper maroon shade for headers and pressed states.
  static const deepIndigo = Color(0xFF5A0A10);
  /// Metallic gold accent (floral motifs, highlights).
  static const saffron = Color(0xFFC8931F);
  /// Warm cream page background.
  static const cream = Color(0xFFFBF3DC);
  /// Deep brown-black text.
  static const ink = Color(0xFF3A1210);
  /// Warm muted text.
  static const muted = Color(0xFF7B6157);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFC0392B);
  /// Light gold used for borders / soft fills.
  static const goldSoft = Color(0xFFE8C46A);
  static const border = Color(0xFFE9DCC0);
}

class NyotaTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NyotaColors.royalPurple,
        primary: NyotaColors.royalPurple,
        secondary: NyotaColors.saffron,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: NyotaColors.cream,
      fontFamily: null,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: NyotaColors.royalPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NyotaColors.royalPurple,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NyotaColors.royalPurple,
          minimumSize: const Size(0, 52),
          side: const BorderSide(color: NyotaColors.royalPurple, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NyotaColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NyotaColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NyotaColors.royalPurple, width: 1.6),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: NyotaColors.royalPurple,
        unselectedItemColor: NyotaColors.muted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
