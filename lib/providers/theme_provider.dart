import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppPalette {
  static const Color accent = Color(0xFF3B82F6);
  static const Color navy = Color(0xFF0F172A);
  static const Color steel = Color(0xFF475569);
  static const Color mint = Color(0xFF10B981);
  static const Color coral = Color(0xFFDC2626);
  static const Color sky = Color(0xFF38BDF8);
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color panel = Colors.white;
  static const Color border = Color(0xFFE2E8F0);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color inkSoft = Color(0xFF94A3B8);
}

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  ThemeData get lightTheme => _buildTheme(Brightness.light);

  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.accent,
      brightness: brightness,
    ).copyWith(
      primary: AppPalette.accent,
      onPrimary: Colors.white,
      secondary: AppPalette.mint,
      tertiary: AppPalette.sky,
      surface: isDark ? const Color(0xFF111C2F) : AppPalette.panel,
      onSurface: isDark ? Colors.white : AppPalette.navy,
      error: AppPalette.coral,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF08111F) : AppPalette.canvas,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        headlineLarge: GoogleFonts.inter(
          textStyle: base.textTheme.headlineLarge,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: GoogleFonts.inter(
          textStyle: base.textTheme.headlineMedium,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.inter(
          textStyle: base.textTheme.titleLarge,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.inter(
          textStyle: base.textTheme.titleMedium,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? const Color(0xFF08111F)
            : Colors.white.withValues(alpha: 0.88),
        foregroundColor: isDark ? Colors.white : AppPalette.navy,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? Colors.white.withValues(alpha: 0.06) : AppPalette.canvas,
        hintStyle: TextStyle(
          color:
              isDark ? Colors.white54 : AppPalette.steel.withValues(alpha: 0.7),
        ),
        labelStyle: TextStyle(
          color: isDark ? Colors.white70 : AppPalette.steel,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : AppPalette.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : AppPalette.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.accent, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : AppPalette.navy,
          side: BorderSide(
            color: isDark ? Colors.white24 : AppPalette.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : AppPalette.border,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
