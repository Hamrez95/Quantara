import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/quantara_theme.dart';
import '../features/cockpit/data/cockpit_repository_factory.dart';
import '../features/cockpit/domain/cockpit_models.dart';
import '../features/cockpit/presentation/cockpit_page.dart';

class QuantaraApp extends StatefulWidget {
  const QuantaraApp({
    super.key,
    this.repository,
    this.initialThemeMode = ThemeMode.dark,
  });

  final CockpitRepository? repository;
  final ThemeMode initialThemeMode;

  @override
  State<QuantaraApp> createState() => _QuantaraAppState();
}

class _QuantaraAppState extends State<QuantaraApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late final CockpitRepository _repository =
      widget.repository ?? CockpitRepositoryFactory.create();

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quantara',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: QuantaraTheme.light(),
      darkTheme: QuantaraTheme.dark(),
      themeMode: _themeMode,
      home: CockpitPage(
        repository: _repository,
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
