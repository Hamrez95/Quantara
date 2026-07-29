import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

abstract final class QuantaraColors {
  static const ink = Color(0xFF07090D);
  static const deepNavy = Color(0xFF0B0E14);
  static const navy = Color(0xFF11151D);
  static const elevatedNavy = Color(0xFF181D27);
  static const cyan = Color(0xFF22B8A5);
  static const violet = Color(0xFF8175F5);
  static const success = Color(0xFF22B8A5);
  static const warning = Color(0xFFF4B740);
  static const danger = Color(0xFFF04452);
  static const muted = Color(0xFF8A93A3);
  static const softBorder = Color(0xFF2A303A);
  static const lightCanvas = Color(0xFFF4F6F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFDDE2E8);
}

abstract final class QuantaraSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class QuantaraRadius {
  static const control = 10.0;
  static const card = 14.0;
  static const large = 18.0;
}

abstract final class QuantaraMotion {
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;
}

abstract final class QuantaraTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: QuantaraColors.cyan,
      onPrimary: QuantaraColors.ink,
      secondary: QuantaraColors.violet,
      onSecondary: Colors.white,
      surface: QuantaraColors.navy,
      onSurface: Color(0xFFF1F3F7),
      surfaceContainerHighest: QuantaraColors.elevatedNavy,
      onSurfaceVariant: QuantaraColors.muted,
      error: QuantaraColors.danger,
      onError: Colors.white,
      outline: QuantaraColors.softBorder,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: QuantaraColors.ink,
      dividerColor: QuantaraColors.softBorder,
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: QuantaraColors.deepNavy,
        indicatorColor: Color(0x2622B8A5),
        selectedIconTheme: IconThemeData(color: QuantaraColors.cyan),
        unselectedIconTheme: IconThemeData(color: QuantaraColors.muted),
        selectedLabelTextStyle: TextStyle(
          color: QuantaraColors.cyan,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: QuantaraColors.muted),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: QuantaraColors.deepNavy,
        indicatorColor: Color(0x2622B8A5),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
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
      surfaceContainerHighest: Color(0xFFF0F3F6),
      onSurfaceVariant: Color(0xFF64748B),
      error: Color(0xFFB42338),
      onError: Colors.white,
      outline: QuantaraColors.lightBorder,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: QuantaraColors.lightCanvas,
      dividerColor: QuantaraColors.lightBorder,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: QuantaraColors.lightSurface,
        indicatorColor: scheme.primary.withValues(alpha: 0.1),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: const IconThemeData(color: Color(0xFF64748B)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: QuantaraColors.lightSurface,
        indicatorColor: scheme.primary.withValues(alpha: 0.1),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        ),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final baseText = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      fontFamily: 'Vazirmatn',
      fontFamilyFallback: const ['Roboto', 'Arial'],
    ).textTheme;
    const numericFeatures = [FontFeature.tabularFigures()];

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Vazirmatn',
      fontFamilyFallback: const ['Roboto', 'Arial'],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontSize: 24,
          height: 1.3,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontSize: 20,
          height: 1.35,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontSize: 14,
          height: 1.42,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
        bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
        bodySmall: baseText.bodySmall?.copyWith(fontSize: 12, height: 1.45),
        labelLarge: baseText.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: baseText.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantaraRadius.card),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.78)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.72),
        thickness: 0.8,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary.withValues(alpha: 0.14),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.75)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantaraRadius.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: baseText.labelMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(QuantaraRadius.control),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(QuantaraRadius.control),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(QuantaraRadius.control),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuantaraRadius.control),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 46),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuantaraRadius.control),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuantaraRadius.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuantaraRadius.control),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(QuantaraRadius.control),
          border: Border.all(color: scheme.outline),
        ),
        textStyle: TextStyle(color: scheme.onSurface),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        QuantaraMarketTypography(numericFeatures: numericFeatures),
      ],
    );
  }
}

@immutable
class QuantaraMarketTypography
    extends ThemeExtension<QuantaraMarketTypography> {
  const QuantaraMarketTypography({required this.numericFeatures});

  final List<FontFeature> numericFeatures;

  TextStyle numeric(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(fontFeatures: numericFeatures);

  @override
  QuantaraMarketTypography copyWith({List<FontFeature>? numericFeatures}) {
    return QuantaraMarketTypography(
      numericFeatures: numericFeatures ?? this.numericFeatures,
    );
  }

  @override
  QuantaraMarketTypography lerp(
    covariant QuantaraMarketTypography? other,
    double t,
  ) {
    return other ?? this;
  }
}
