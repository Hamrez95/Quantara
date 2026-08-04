import 'package:flutter/material.dart';

abstract final class QuantaraColors {
  static const ink = Color(0xFF030711);
  static const deepNavy = Color(0xFF07101D);
  static const navy = Color(0xFF0C1626);
  static const elevatedNavy = Color(0xFF121F32);
  static const raisedNavy = Color(0xFF19283D);
  static const cyan = Color(0xFF20D6C7);
  static const electricBlue = Color(0xFF4A8FFF);
  static const violet = Color(0xFF8C6CFF);
  static const magenta = Color(0xFFE85CCB);
  static const success = Color(0xFF25D2A8);
  static const warning = Color(0xFFF6B94A);
  static const danger = Color(0xFFFF5C70);
  static const muted = Color(0xFF91A0B6);
  static const softBorder = Color(0xFF23344C);
  static const lightCanvas = Color(0xFFF2F5FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFD9E1EC);

  static const brandGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [cyan, electricBlue, violet],
  );
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
  static const control = 14.0;
  static const card = 20.0;
  static const large = 26.0;
}

abstract final class QuantaraMotion {
  static const fast = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 360);
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
      onSurface: Color(0xFFF4F7FB),
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
        indicatorColor: Color(0x3320D6C7),
        selectedIconTheme: IconThemeData(color: QuantaraColors.cyan),
        unselectedIconTheme: IconThemeData(color: QuantaraColors.muted),
        selectedLabelTextStyle: TextStyle(
          color: QuantaraColors.cyan,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: TextStyle(color: QuantaraColors.muted),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: QuantaraColors.deepNavy,
        indicatorColor: Color(0x3320D6C7),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
        ),
      ),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: Color(0xFF087F78),
      onPrimary: Colors.white,
      secondary: Color(0xFF6955DD),
      onSecondary: Colors.white,
      surface: QuantaraColors.lightSurface,
      onSurface: Color(0xFF142033),
      surfaceContainerHighest: Color(0xFFEDF2F8),
      onSurfaceVariant: Color(0xFF627187),
      error: Color(0xFFBA2D48),
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
        height: 72,
        backgroundColor: QuantaraColors.lightSurface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
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
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.brightness == Brightness.dark
            ? QuantaraColors.deepNavy
            : QuantaraColors.lightSurface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        titleSpacing: 14,
        shape: Border(
          bottom: BorderSide(
            color: scheme.outline.withValues(alpha: 0.55),
            width: 0.8,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface, height: 1.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantaraRadius.card),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        ),
      ),
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontSize: 24,
          height: 1.28,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.55,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontSize: 19,
          height: 1.34,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.25,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontSize: 15.5,
          height: 1.4,
          fontWeight: FontWeight.w800,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontSize: 13.5,
          height: 1.42,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 15, height: 1.55),
        bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 13.5, height: 1.52),
        bodySmall: baseText.bodySmall?.copyWith(fontSize: 11.8, height: 1.48),
        labelLarge: baseText.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        labelMedium: baseText.labelMedium?.copyWith(
          fontSize: 11.8,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QuantaraRadius.card),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.75)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.68),
        thickness: 0.8,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary.withValues(alpha: 0.14),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.72)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: baseText.labelMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.78),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
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
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
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
