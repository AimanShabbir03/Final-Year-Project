import 'package:flutter/material.dart';

/// App-wide theme and responsive helpers for School Pick & Drop.
class AppTheme {
  AppTheme._();

  // Colors - modern, high contrast palette for transport/safety
  static const Color primary = Color(0xFF0E7490);
  static const Color primaryDark = Color(0xFF155E75);
  static const Color primaryLight = Color(0xFF67E8F9);
  static const Color accent = Color(0xFFF59E0B);
  static const Color surface = Color(0xFFF5F8FF);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color divider = Color(0xFFDCE4F2);
  static const Color appBarForeground = Colors.white;
  static const Color subtleSurface = Color(0xFFECF3FF);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: accent,
          surface: surface,
          onPrimary: Colors.white,
          onSurface: textPrimary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: surface,
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: primary,
          foregroundColor: appBarForeground,
          titleTextStyle: const TextStyle(
            color: appBarForeground,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.3,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
          labelLarge: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: divider),
          ),
          color: cardBg,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: error, width: 2),
          ),
          labelStyle: const TextStyle(color: textSecondary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: appBarForeground,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: const BorderSide(color: primary),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  static LinearGradient get pageGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE9F7FF),
          Color(0xFFF4FBFF),
          Color(0xFFFFFFFF),
        ],
      );

  static BoxDecoration get glassCardDecoration => BoxDecoration(
        color: Colors.white.withOpacity(0.93),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      );

  /// Horizontal padding that scales with screen width (responsive).
  static double horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 12;
    if (w < 600) return 16;
    return 24;
  }

  /// Vertical spacing that scales.
  static double verticalSpacing(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    if (h < 600) return 8;
    if (h < 800) return 12;
    return 16;
  }

  /// Safe padding including notch/status bar.
  static EdgeInsets padding(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final h = horizontalPadding(context);
    return EdgeInsets.fromLTRB(h, top, h, bottom);
  }

  /// Content padding (no safe area).
  static EdgeInsets contentPadding(BuildContext context) {
    final h = horizontalPadding(context);
    final v = verticalSpacing(context) * 1.5;
    return EdgeInsets.symmetric(horizontal: h, vertical: v);
  }

  /// Whether we're on a narrow (phone) screen.
  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  /// Max content width for very large screens (e.g. tablet).
  static double maxContentWidth = 480;
}
