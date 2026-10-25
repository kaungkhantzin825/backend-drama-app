import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The app's visual language.
///
/// Short-drama apps are watched in the dark, on a phone, for a minute at a
/// time — so the palette is near-black with one saturated accent, and type is
/// large enough to read at arm's length.
class AppTheme {
  const AppTheme._();

  /// Brand accent — used for the primary action, the points pill and progress.
  static const Color accent = Color(0xFFE50914);
  static const Color accentDark = Color(0xFFB0060F);

  /// Points/currency highlight. Warm gold reads as "value" without competing
  /// with the accent red.
  static const Color gold = Color(0xFFFFC145);

  static const Color background = Color(0xFF0B0B0F);
  static const Color surface = Color(0xFF15151C);
  static const Color surfaceHigh = Color(0xFF1E1E28);
  static const Color divider = Color(0xFF2A2A36);

  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFF9A9AA8);
  static const Color success = Color(0xFF34C759);

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Colors.white,
      secondary: gold,
      onSecondary: Color(0xFF231A00),
      surface: surface,
      onSurface: textPrimary,
      error: accent,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: textPrimary,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        headlineSmall: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12, height: 1.4),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1, space: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
