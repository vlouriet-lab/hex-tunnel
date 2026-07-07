import 'package:flutter/material.dart';

/// Тёмная фиолетовая тема приложения Hex Decensor.
/// Стиль вдохновлён расширением Red Shield VPN и браузером SOTA Segment.
class AppTheme {
  AppTheme._();

  static const Duration motionFast = Duration(milliseconds: 280);
  static const Duration motionMedium = Duration(milliseconds: 420);
  static const Duration motionPulse = Duration(milliseconds: 2200);
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  // ── Цветовая палитра ──────────────────────────────────────────────────────

  static const Color background = Color(0xFF0A0A1A); // Глубокий тёмно-синий
  static const Color surface = Color(0xFF12112A); // Поверхность карточек
  static const Color surfaceVariant =
      Color(0xFF1A1835); // Поверхность элементов

  static const Color primary = Color(0xFF7C3AED); // Фиолетовый акцент
  static const Color primaryLight = Color(0xFF9D5CF6); // Светлее (hover/active)
  static const Color primaryDark = Color(0xFF5B21B6); // Темнее (pressed)
  static const Color primaryGlow = Color(0x407C3AED); // Свечение кнопки

  static const Color connected = Color(0xFF10B981); // Зелёный — подключено
  static const Color connecting = Color(0xFFF59E0B); // Янтарный — подключение
  static const Color disconnected = Color(0xFF374151); // Серый — отключено
  static const Color error = Color(0xFFEF4444); // Красный — ошибка

  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFF4B5563);

  static const Color hexLine = Color(0x18A855F7); // Линии гексагонов
  static const Color hexLineBright = Color(0x30A855F7);
  static const Color border = Color(0xFF1F1D3D);

  // ── ThemeData ─────────────────────────────────────────────────────────────

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Color(0xFFFFFFFF),
        secondary: primaryLight,
        onSecondary: Color(0xFFFFFFFF),
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: Color(0xFFFFFFFF),
      ),
      fontFamily: 'SF Pro Display',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          letterSpacing: 0.1,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          color: textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textSecondary,
          letterSpacing: 0.8,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textDisabled,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 0,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          enableFeedback: false,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          enableFeedback: false,
          animationDuration: motionFast,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          enableFeedback: false,
          animationDuration: motionFast,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          enableFeedback: false,
          animationDuration: motionFast,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textDisabled),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: textPrimary,
        iconColor: textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
