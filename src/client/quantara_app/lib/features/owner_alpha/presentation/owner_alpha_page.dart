import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/formatting/number_formatters.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/local_live_message_localizer.dart';
import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../../auto_trade/application/auto_trade_controller.dart';
import '../../auto_trade/application/unattended_auto_trade_controller.dart';
import '../../auto_trade/data/bitunix_private_api_client.dart';
import '../../auto_trade/data/secure_auto_trade_credentials_store.dart';
import '../../auto_trade/data/secure_auto_trade_server_config_store.dart';
import '../../auto_trade/data/unattended_auto_trade_api_client.dart';
import '../../auto_trade/domain/auto_trade_models.dart';
import '../../auto_trade/domain/unattended_auto_trade_models.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/presentation/tradingview_lightweight_chart.dart';
import '../../strategy_lab/data/strategy_lab_runner.dart';
import '../../strategy_lab/data/platform_strategy_lab_session_store.dart';
import '../../strategy_lab/domain/strategy_lab_models.dart';
import '../application/owner_alpha_controller.dart';
import '../data/owner_alpha_settings_transfer.dart';
import '../data/signal_timeframe_priority.dart';
import '../domain/owner_alpha_models.dart';

part 'owner_alpha_dashboard.dart';
part 'owner_alpha_watchlist.dart';
part 'owner_alpha_signals.dart';
part 'owner_alpha_analysis.dart';
part 'owner_alpha_auto_trade.dart';
part 'owner_alpha_auto_trade_support.dart';
part 'owner_alpha_auto_trade_unattended.dart';
part 'owner_alpha_exchange.dart';
part 'owner_alpha_strategy.dart';
part 'owner_alpha_strategy_lab.dart';

typedef _OpenAnalysis =
    void Function(String symbol, [String? timeframe, String? setupId]);

class OwnerAlphaPage extends StatefulWidget {
  const OwnerAlphaPage({
    required this.repository,
    required this.settingsStore,
    this.opportunityStateStore,
    this.notificationGateway = const NoopSetupNotificationGateway(),
    this.backgroundScanGateway = const NoopBackgroundScanGateway(),
    required this.themeMode,
    required this.locale,
    required this.onToggleTheme,
    required this.onLocaleChanged,
    super.key,
  });

  final OwnerAlphaRepository repository;
  final OwnerAlphaSettingsStore settingsStore;
  final OpportunityStateStore? opportunityStateStore;
  final SetupNotificationGateway notificationGateway;
  final BackgroundScanGateway backgroundScanGateway;
  final ThemeMode themeMode;
  final Locale locale;
  final VoidCallback onToggleTheme;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<OwnerAlphaPage> createState() => _OwnerAlphaPageState();
}

class _OwnerAlphaPageState extends State<OwnerAlphaPage> {
  late final http.Client _autoTradeHttpClient = http.Client();
  late final AutoTradeController _autoTradeController = AutoTradeController(
    apiClient: BitunixPrivateApiClient(client: _autoTradeHttpClient),
    credentialsStore: const SecureAutoTradeCredentialsStore(),
  );
  late final UnattendedAutoTradeController _unattendedAutoTradeController =
      UnattendedAutoTradeController(
        apiClient: UnattendedAutoTradeApiClient(client: _autoTradeHttpClient),
        configStore: const SecureAutoTradeServerConfigStore(),
      );
  late final OwnerAlphaController _controller = OwnerAlphaController(
    repository: widget.repository,
    settingsStore: widget.settingsStore,
    opportunityStateStore: widget.opportunityStateStore,
    notificationGateway: widget.notificationGateway,
    backgroundScanGateway: widget.backgroundScanGateway,
    languageCode: widget.locale.languageCode,
  );
  int _destination = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
    unawaited(_autoTradeController.initialize());
    unawaited(_unattendedAutoTradeController.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    _autoTradeController.dispose();
    _unattendedAutoTradeController.dispose();
    _autoTradeHttpClient.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OwnerAlphaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locale.languageCode != widget.locale.languageCode) {
      _controller.setLanguage(widget.locale.languageCode, notify: false);
    }
  }

  void _openAnalysis(String symbol, [String? timeframe, String? setupId]) {
    unawaited(_openAnalysisContext(symbol, timeframe, setupId));
  }

  Future<void> _openAnalysisContext(
    String symbol,
    String? timeframe,
    String? setupId,
  ) async {
    final opened = await _controller.selectChartContext(
      symbol: symbol,
      timeframe: timeframe ?? _controller.selectedTimeframe,
      setupId: setupId,
    );
    if (!mounted) return;
    if (opened) {
      setState(() => _destination = 2);
      return;
    }
    final persian = widget.locale.languageCode != 'en';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          persian
              ? 'زمینه دقیق این پیشنهاد فعلاً در واچ‌لیست یا داده بازار موجود نیست.'
              : 'The exact signal context is not currently available in the watchlist or market data.',
        ),
      ),
    );
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
            autoTradeController: _autoTradeController,
            unattendedAutoTradeController: _unattendedAutoTradeController,
            destination: _destination,
            themeMode: widget.themeMode,
            locale: widget.locale,
            onToggleTheme: widget.onToggleTheme,
            onLocaleChanged: widget.onLocaleChanged,
            onOpenAnalysis: _openAnalysis,
            onAddSymbol: _showAddSymbolDialog,
            onOpenStrategyLab: () => setState(() => _destination = 4),
            showTopBar: desktop,
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
                  Expanded(
                    child: _DestinationTransition(
                      destination: _destination,
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          appBar: _QuantaraMobileAppBar(
            controller: _controller,
            destination: _destination,
            themeMode: widget.themeMode,
            onToggleTheme: widget.onToggleTheme,
            onRefresh: _controller.refresh,
          ),
          body: SafeArea(
            bottom: false,
            child: _DestinationTransition(
              destination: _destination,
              child: body,
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: _mobileDestinationIndexes.contains(_destination)
                  ? _mobileDestinationIndexes.indexOf(_destination)
                  : 2,
              labelBehavior: constraints.maxWidth < 440
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (value) {
                setState(() => _destination = _mobileDestinationIndexes[value]);
              },
              destinations: _mobileDestinationIndexes
                  .map(
                    (index) => NavigationDestination(
                      icon: Icon(_destinations[index].icon),
                      selectedIcon: Icon(_destinations[index].selectedIcon),
                      label: _destinationLabel(strings, index),
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

class _DestinationTransition extends StatelessWidget {
  const _DestinationTransition({
    required this.destination,
    required this.child,
  });

  final int destination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : QuantaraMotion.standard,
      switchInCurve: QuantaraMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey('destination-$destination'),
        child: child,
      ),
    );
  }
}

class _QuantaraMobileAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _QuantaraMobileAppBar({
    required this.controller,
    required this.destination,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onRefresh,
  });

  final OwnerAlphaController controller;
  final int destination;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final state = controller.connectionState;
    final healthy =
        state == OwnerAlphaConnectionState.fresh ||
        state == OwnerAlphaConnectionState.refreshing;
    return AppBar(
      leadingWidth: 56,
      leading: const Padding(
        padding: EdgeInsetsDirectional.only(start: 14, top: 10, bottom: 10),
        child: QuantaraBrandMark(size: 40),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quantara',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.55),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: QuantaraMotion.fast,
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: healthy
                      ? QuantaraColors.success
                      : QuantaraColors.warning,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (healthy
                                  ? QuantaraColors.success
                                  : QuantaraColors.warning)
                              .withValues(alpha: 0.35),
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _destinationLabel(strings, destination),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: controller.isLoading ? null : onRefresh,
          tooltip: strings.isPersian ? 'به‌روزرسانی' : 'Refresh',
          icon: AnimatedRotation(
            duration: QuantaraMotion.standard,
            turns: controller.isLoading ? 0.5 : 0,
            child: const Icon(Icons.refresh_rounded),
          ),
        ),
        IconButton(
          onPressed: onToggleTheme,
          tooltip: themeMode == ThemeMode.dark
              ? strings.lightAppearance
              : strings.darkAppearance,
          icon: Icon(
            themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
        ),
        const SizedBox(width: 6),
      ],
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
  _Destination(Icons.inbox_outlined, Icons.inbox_rounded),
  _Destination(
    Icons.candlestick_chart_outlined,
    Icons.candlestick_chart_rounded,
  ),
  _Destination(Icons.view_list_outlined, Icons.view_list_rounded),
  _Destination(Icons.science_outlined, Icons.science_rounded),
  _Destination(Icons.smart_toy_outlined, Icons.smart_toy_rounded),
  _Destination(Icons.person_outline_rounded, Icons.person_rounded),
];
const _mobileDestinationIndexes = [0, 1, 2, 3, 5, 6];

String _destinationLabel(AppStrings strings, int index) => switch (index) {
  1 => strings.setups,
  2 => strings.analysis,
  3 => strings.watchlist,
  4 => strings.strategyLab,
  5 => strings.isPersian ? 'ترید خودکار' : 'Auto Trade',
  6 => strings.profile,
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
    required this.autoTradeController,
    required this.unattendedAutoTradeController,
    required this.destination,
    required this.themeMode,
    required this.locale,
    required this.onToggleTheme,
    required this.onLocaleChanged,
    required this.onOpenAnalysis,
    required this.onAddSymbol,
    required this.onOpenStrategyLab,
    required this.showTopBar,
  });

  final OwnerAlphaController controller;
  final AutoTradeController autoTradeController;
  final UnattendedAutoTradeController unattendedAutoTradeController;
  final int destination;
  final ThemeMode themeMode;
  final Locale locale;
  final VoidCallback onToggleTheme;
  final ValueChanged<Locale> onLocaleChanged;
  final _OpenAnalysis onOpenAnalysis;
  final VoidCallback onAddSymbol;
  final VoidCallback onOpenStrategyLab;
  final bool showTopBar;

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
                  if (showTopBar) ...[
                    _AlphaTopBar(
                      controller: controller,
                      themeMode: themeMode,
                      onToggleTheme: onToggleTheme,
                    ),
                    const SizedBox(height: 14),
                  ],
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
                  if (destination == 6)
                    _ProfileView(
                      controller: controller,
                      themeMode: themeMode,
                      locale: locale,
                      onToggleTheme: onToggleTheme,
                      onLocaleChanged: onLocaleChanged,
                    )
                  else if (destination == 5)
                    _AutoTradeView(
                      controller: autoTradeController,
                      unattendedController: unattendedAutoTradeController,
                      analysisController: controller,
                    )
                  else if (controller.snapshot == null)
                    _InitialLoading(controller: controller)
                  else
                    switch (destination) {
                      1 => _SignalInboxView(
                        controller: controller,
                        onOpenAnalysis: onOpenAnalysis,
                      ),
                      2 => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onOpenStrategyLab,
                            icon: const Icon(Icons.science_outlined),
                            label: Text(AppStrings.of(context).openStrategyLab),
                          ),
                          const SizedBox(height: 14),
                          _AlphaAnalysisView(
                            controller: controller,
                            snapshot: controller.snapshot!,
                          ),
                        ],
                      ),
                      3 => _WatchlistView(
                        controller: controller,
                        snapshot: controller.snapshot!,
                        onOpenAnalysis: onOpenAnalysis,
                        onAddSymbol: onAddSymbol,
                      ),
                      4 => _StrategyLabView(
                        controller: controller,
                        snapshot: controller.snapshot!,
                      ),
                      _ => _RadarDashboard(
                        controller: controller,
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
    return QuantaraBrandMark(size: size);
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
