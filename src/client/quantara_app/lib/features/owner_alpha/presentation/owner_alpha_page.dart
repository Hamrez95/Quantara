import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/presentation/tradingview_lightweight_chart.dart';
import '../application/owner_alpha_controller.dart';
import '../domain/owner_alpha_models.dart';

part 'owner_alpha_dashboard.dart';
part 'owner_alpha_watchlist.dart';
part 'owner_alpha_analysis.dart';
part 'owner_alpha_exchange.dart';

class OwnerAlphaPage extends StatefulWidget {
  const OwnerAlphaPage({
    required this.repository,
    required this.settingsStore,
    required this.themeMode,
    required this.locale,
    required this.onToggleTheme,
    required this.onLocaleChanged,
    super.key,
  });

  final OwnerAlphaRepository repository;
  final OwnerAlphaSettingsStore settingsStore;
  final ThemeMode themeMode;
  final Locale locale;
  final VoidCallback onToggleTheme;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<OwnerAlphaPage> createState() => _OwnerAlphaPageState();
}

class _OwnerAlphaPageState extends State<OwnerAlphaPage> {
  late final OwnerAlphaController _controller = OwnerAlphaController(
    repository: widget.repository,
    settingsStore: widget.settingsStore,
    languageCode: widget.locale.languageCode,
  );
  int _destination = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OwnerAlphaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locale.languageCode != widget.locale.languageCode) {
      _controller.setLanguage(widget.locale.languageCode, notify: false);
    }
  }

  void _openAnalysis(String symbol) {
    unawaited(_controller.selectSymbol(symbol));
    setState(() => _destination = 2);
  }

  Future<void> _showAddSymbolDialog() async {
    final strings = AppStrings.of(context);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _AddSymbolDialog(strings: strings),
    );
    if (value == null || !mounted) {
      return;
    }
    final error = await _controller.addSymbol(value);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final strings = AppStrings.of(context);
        final desktop = constraints.maxWidth >= 1024;
        final body = AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _OwnerAlphaBody(
            controller: _controller,
            destination: _destination,
            themeMode: widget.themeMode,
            locale: widget.locale,
            onToggleTheme: widget.onToggleTheme,
            onLocaleChanged: widget.onLocaleChanged,
            onOpenAnalysis: _openAnalysis,
            onAddSymbol: _showAddSymbolDialog,
          ),
        );
        if (desktop) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    extended: constraints.maxWidth >= 1320,
                    minExtendedWidth: 220,
                    selectedIndex: _destination,
                    onDestinationSelected: (value) {
                      setState(() => _destination = value);
                    },
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: _AlphaLogo(size: 44),
                    ),
                    destinations: _destinations.indexed
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.$2.icon),
                            selectedIcon: Icon(item.$2.selectedIcon),
                            label: Text(_destinationLabel(strings, item.$1)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: SafeArea(bottom: false, child: body),
          bottomNavigationBar: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: _destination,
              labelBehavior: constraints.maxWidth < 380
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (value) {
                setState(() => _destination = value);
              },
              destinations: _destinations.indexed
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.$2.icon),
                      selectedIcon: Icon(item.$2.selectedIcon),
                      label: _destinationLabel(strings, item.$1),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }
}

class _AddSymbolDialog extends StatefulWidget {
  const _AddSymbolDialog({required this.strings});

  final AppStrings strings;

  @override
  State<_AddSymbolDialog> createState() => _AddSymbolDialogState();
}

class _AddSymbolDialogState extends State<_AddSymbolDialog> {
  final TextEditingController _textController = TextEditingController();
  String? _validation;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _textController.text.trim();
    if (value.isEmpty) {
      setState(() => _validation = widget.strings.symbolRequired);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(strings.addSymbolTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.addSymbolDescription),
            const SizedBox(height: 14),
            TextField(
              controller: _textController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'Symbol',
                hintText: 'XRPUSDT',
                errorText: _validation,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(strings.verifyAndAdd)),
      ],
    );
  }
}

const _destinations = [
  _Destination(Icons.radar_outlined, Icons.radar_rounded),
  _Destination(Icons.view_list_outlined, Icons.view_list_rounded),
  _Destination(
    Icons.candlestick_chart_outlined,
    Icons.candlestick_chart_rounded,
  ),
  _Destination(Icons.person_outline_rounded, Icons.person_rounded),
];

String _destinationLabel(AppStrings strings, int index) => switch (index) {
  1 => strings.watchlist,
  2 => strings.analysis,
  3 => strings.profile,
  _ => strings.radar,
};

final class _Destination {
  const _Destination(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;
}

class _OwnerAlphaBody extends StatelessWidget {
  const _OwnerAlphaBody({
    required this.controller,
    required this.destination,
    required this.themeMode,
    required this.locale,
    required this.onToggleTheme,
    required this.onLocaleChanged,
    required this.onOpenAnalysis,
    required this.onAddSymbol,
  });

  final OwnerAlphaController controller;
  final int destination;
  final ThemeMode themeMode;
  final Locale locale;
  final VoidCallback onToggleTheme;
  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<String> onOpenAnalysis;
  final VoidCallback onAddSymbol;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: PageStorageKey('owner-alpha-$destination'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 14, wide ? 28 : 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AlphaTopBar(
                    controller: controller,
                    themeMode: themeMode,
                    onToggleTheme: onToggleTheme,
                  ),
                  const SizedBox(height: 14),
                  const _LiveBoundaryStrip(),
                  if (controller.error != null) ...[
                    const SizedBox(height: 12),
                    _AlphaErrorStrip(
                      message: controller.error!,
                      stale: controller.hasStaleSnapshot,
                      onRetry: controller.refresh,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (destination == 3)
                    _ProfileView(
                      controller: controller,
                      themeMode: themeMode,
                      locale: locale,
                      onToggleTheme: onToggleTheme,
                      onLocaleChanged: onLocaleChanged,
                    )
                  else if (controller.snapshot == null)
                    _InitialLoading(controller: controller)
                  else
                    switch (destination) {
                      1 => _WatchlistView(
                        controller: controller,
                        snapshot: controller.snapshot!,
                        onOpenAnalysis: onOpenAnalysis,
                        onAddSymbol: onAddSymbol,
                      ),
                      2 => _AlphaAnalysisView(
                        controller: controller,
                        snapshot: controller.snapshot!,
                      ),
                      _ => _RadarDashboard(
                        snapshot: controller.snapshot!,
                        onOpenAnalysis: onOpenAnalysis,
                      ),
                    },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlphaTopBar extends StatelessWidget {
  const _AlphaTopBar({
    required this.controller,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final OwnerAlphaController controller;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final identity = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quantara',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          Text(
            strings.appSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
    final themeButton = IconButton.filledTonal(
      onPressed: onToggleTheme,
      tooltip: themeMode == ThemeMode.dark
          ? strings.lightAppearance
          : strings.darkAppearance,
      icon: Icon(
        themeMode == ThemeMode.dark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final firstRow = Row(
          children: [
            const _AlphaLogo(size: 46),
            const SizedBox(width: 12),
            identity,
            if (!compact) ...[
              _ConnectionStatusPill(controller: controller),
              const SizedBox(width: 6),
            ],
            themeButton,
          ],
        );
        if (!compact) {
          return firstRow;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            firstRow,
            const SizedBox(height: 10),
            _ConnectionStatusPill(controller: controller),
          ],
        );
      },
    );
  }
}

class _LiveBoundaryStrip extends StatelessWidget {
  const _LiveBoundaryStrip();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuantaraColors.cyan.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuantaraColors.cyan.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined, color: QuantaraColors.cyan),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.liveBoundary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusPill extends StatelessWidget {
  const _ConnectionStatusPill({required this.controller});

  final OwnerAlphaController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final state = controller.connectionState;
    final label = switch (state) {
      OwnerAlphaConnectionState.connecting => strings.connecting,
      OwnerAlphaConnectionState.refreshing => strings.refreshing,
      OwnerAlphaConnectionState.fresh => strings.liveMarketData,
      OwnerAlphaConnectionState.stale => strings.delayedData,
      OwnerAlphaConnectionState.unavailable => strings.unavailable,
    };
    final healthy =
        state == OwnerAlphaConnectionState.fresh ||
        state == OwnerAlphaConnectionState.refreshing;
    return StatusPill(
      label: label,
      color: healthy ? QuantaraColors.success : QuantaraColors.warning,
      icon: healthy ? Icons.wifi_rounded : Icons.wifi_off_rounded,
    );
  }
}

class _AlphaErrorStrip extends StatelessWidget {
  const _AlphaErrorStrip({
    required this.message,
    required this.stale,
    required this.onRetry,
  });

  final String message;
  final bool stale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_off_rounded, color: scheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stale ? strings.staleSuffix(message) : message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: onRetry, child: Text(strings.retry)),
          ),
        ],
      ),
    );
  }
}

class _InitialLoading extends StatelessWidget {
  const _InitialLoading({required this.controller});

  final OwnerAlphaController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Column(
          children: [
            if (controller.isLoading)
              const CircularProgressIndicator()
            else
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
            const SizedBox(height: 18),
            Text(
              controller.isLoading
                  ? strings.initialLoading
                  : strings.noValidMarketData,
              textAlign: TextAlign.center,
            ),
            if (!controller.isLoading) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.tryAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlphaLogo extends StatelessWidget {
  const _AlphaLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [QuantaraColors.cyan, QuantaraColors.violet],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            'Q',
            style: TextStyle(
              color: QuantaraColors.ink,
              fontSize: size * 0.48,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

Color _ideaColor(BuildContext context, TradeDirection direction) {
  return switch (direction) {
    TradeDirection.long => QuantaraColors.success,
    TradeDirection.short => QuantaraColors.danger,
    TradeDirection.wait => Theme.of(context).colorScheme.secondary,
  };
}

String _ideaLabel(BuildContext context, TradeDirection direction) {
  return AppStrings.of(context).idea(direction.name);
}

String _directionLabel(BuildContext context, ChartDirection direction) {
  return AppStrings.of(context).direction(direction.name);
}

Color _chartDirectionColor(ChartDirection direction) {
  return switch (direction) {
    ChartDirection.bullish => QuantaraColors.success,
    ChartDirection.bearish => QuantaraColors.danger,
    ChartDirection.sideways => QuantaraColors.warning,
  };
}
