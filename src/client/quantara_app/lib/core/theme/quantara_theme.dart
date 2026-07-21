import 'package:flutter/material.dart';

abstract final class QuantaraColors {
  static const ink = Color(0xFF07101F);
  static const deepNavy = Color(0xFF0B1528);
  static const navy = Color(0xFF111D33);
  static const elevatedNavy = Color(0xFF17243D);
  static const cyan = Color(0xFF43D7C4);
  static const violet = Color(0xFF8175F5);
  static const success = Color(0xFF39D58A);
  static const warning = Color(0xFFFFBF5B);
  static const danger = Color(0xFFFF7280);
  static const muted = Color(0xFF92A2BD);
  static const softBorder = Color(0xFF253654);
  static const lightCanvas = Color(0xFFF3F6FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFD9E1EC);
}

abstract final class QuantaraTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: QuantaraColors.cyan,
      onPrimary: QuantaraColors.ink,
      secondary: QuantaraColors.violet,
      onSecondary: Colors.white,
      surface: QuantaraColors.navy,
      onSurface: Color(0xFFF5F8FF),
      error: QuantaraColors.danger,
      onError: QuantaraColors.ink,
      outline: QuantaraColors.softBorder,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: QuantaraColors.ink,
      dividerColor: QuantaraColors.softBorder,
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: QuantaraColors.deepNavy,
        indicatorColor: Color(0x3343D7C4),
        selectedIconTheme: IconThemeData(color: QuantaraColors.cyan),
        unselectedIconTheme: IconThemeData(color: QuantaraColors.muted),
        selectedLabelTextStyle: TextStyle(
          color: QuantaraColors.cyan,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: QuantaraColors.muted),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: QuantaraColors.deepNavy,
        indicatorColor: Color(0x3343D7C4),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: Color(0xFF087F74),
      onPrimary: Colors.white,
      secondary: Color(0xFF6255D8),
      onSecondary: Colors.white,
      surface: QuantaraColors.lightSurface,
      onSurface: Color(0xFF172033),
      error: Color(0xFFB42338),
      onError: Colors.white,
      outline: QuantaraColors.lightBorder,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: QuantaraColors.lightCanvas,
      dividerColor: QuantaraColors.lightBorder,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: QuantaraColors.lightSurface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: const IconThemeData(color: Color(0xFF64748B)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: QuantaraColors.lightSurface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final baseText = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
    ).textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontSize: 25,
          height: 1.35,
        ),
        titleLarge: baseText.titleLarge?.copyWith(fontSize: 21, height: 1.4),
        titleMedium: baseText.titleMedium?.copyWith(fontSize: 17, height: 1.45),
        titleSmall: baseText.titleSmall?.copyWith(fontSize: 15, height: 1.45),
        bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 17, height: 1.55),
        bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
        bodySmall: baseText.bodySmall?.copyWith(fontSize: 13, height: 1.45),
        labelLarge: baseText.labelLarge?.copyWith(fontSize: 14),
        labelMedium: baseText.labelMedium?.copyWith(fontSize: 13),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outline),
        ),
        textStyle: TextStyle(color: scheme.onSurface),
      ),
    );
  }
}

