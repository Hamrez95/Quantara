import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/local_live_message_localizer.dart';
import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../../auto_trade/application/auto_trade_controller.dart';
import '../../auto_trade/application/local_live_diagnostic_bundle.dart';
import '../../auto_trade/application/local_live_trade_service.dart';
import '../../auto_trade/application/read_only_support_session.dart';
import '../../auto_trade/application/unattended_auto_trade_controller.dart';
import '../../auto_trade/data/bitunix_private_api_client.dart';
import '../../auto_trade/data/local_live_preferences_store.dart';
import '../../auto_trade/data/secure_auto_trade_credentials_store.dart';
import '../../auto_trade/data/secure_auto_trade_server_config_store.dart';
import '../../auto_trade/data/unattended_auto_trade_api_client.dart';
import '../../auto_trade/domain/auto_trade_models.dart';
import '../../auto_trade/domain/private_account_reconciliation.dart';
import '../../auto_trade/domain/trading_pnl_projection.dart';
import '../../auto_trade/domain/unattended_auto_trade_models.dart';
import '../../auto_trade/presentation/private_account_reconciliation_banner.dart';
import '../../auto_trade/presentation/position_protection_summary.dart';
import '../../auto_trade/presentation/tp_allocation_editor.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/presentation/tradingview_lightweight_chart.dart';
import '../../trading_journal/application/trading_journal_controller.dart';
import '../../trading_journal/data/database_trading_journal_store.dart';
import '../../trading_journal/domain/trading_journal_evidence_packet.dart';
import '../../trading_journal/presentation/trading_journal_view.dart';
import '../../trading_lab/application/trading_lab_controller.dart';
import '../../trading_lab/data/database_trading_lab_store.dart';
import '../../trading_lab/domain/trading_lab_account_context.dart';
import '../../trading_lab/domain/trading_lab_models.dart';
import '../application/owner_alpha_controller.dart';
import '../application/signal_inbox_query.dart';
import '../data/owner_alpha_settings_transfer.dart';
import '../data/realtime_production_runtime.dart';
import '../data/signal_timeframe_priority.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/profit_protection_policy.dart';
import '../domain/realtime_market_runtime_models.dart';

part 'owner_alpha_dashboard.dart';
part 'owner_alpha_home.dart';
part 'owner_alpha_watchlist.dart';
part 'owner_alpha_signals.dart';
part 'owner_alpha_analysis.dart';
part 'owner_alpha_auto_trade.dart';
part 'owner_alpha_local_live_tools.dart';
part 'owner_alpha_auto_trade_support.dart';
part 'owner_alpha_auto_trade_unattended.dart';
part 'owner_alpha_exchange.dart';
part 'owner_alpha_strategy.dart';
part 'owner_alpha_trading_lab.dart';

typedef _OpenAnalysis =
    void Function(String symbol, [String? timeframe, String? setupId]);

void _noopOpenPortfolioRisk() {}

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
    this.onOpenPortfolioRisk = _noopOpenPortfolioRisk,
    this.realtimeMonitor,
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
  final VoidCallback onOpenPortfolioRisk;
  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;

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
  late final TradingJournalController _journalController =
      TradingJournalController(store: DatabaseTradingJournalStore());
  late final OwnerAlphaController _controller = OwnerAlphaController(
    repository: widget.repository,
    settingsStore: widget.settingsStore,
    opportunityStateStore: widget.opportunityStateStore,
    notificationGateway: widget.notificationGateway,
    backgroundScanGateway: widget.backgroundScanGateway,
    languageCode: widget.locale.languageCode,
  );
  late final TradingLabController _tradingLabController = TradingLabController(
    marketController: _controller,
    store: DatabaseTradingLabRunStore(),
    accountContextProvider: () {
      final reconciliation = _autoTradeController.reconciliation;
      final snapshot = _autoTradeController.snapshot;
      return TradingLabAccountContext(
        connected: _autoTradeController.isConnected,
        reconciliationHealth: reconciliation.health.name,
        refreshing: reconciliation.refreshing,
        blocksNewEntries: reconciliation.blocksNewEntries,
        canManageExistingPositions:
            reconciliation.allowsExistingPositionManagement,
        syncedAtUtc: snapshot?.syncedAt.toUtc(),
        marginCoin: snapshot?.marginCoin,
        available: snapshot?.available,
        frozen: snapshot?.frozen,
        positionMargin: snapshot?.positionMargin,
        unrealizedPnl: snapshot?.totalUnrealizedPnl,
        estimatedEquity: snapshot?.estimatedEquity,
        openPositionCount: snapshot?.positions.length,
        pendingOrderCount: snapshot?.totalPendingOrderCount,
        allOpenPositionsFullyProtected:
            snapshot?.allOpenPositionsFullyProtected,
        warning: reconciliation.warning,
      );
    },
  );
  final GlobalKey<_AutoTradeViewState> _autoTradeViewKey =
      GlobalKey<_AutoTradeViewState>();
  int _destination = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
    unawaited(_tradingLabController.initialize());
    unawaited(_autoTradeController.initialize());
    unawaited(_unattendedAutoTradeController.initialize());
    unawaited(_journalController.initialize());
  }

  @override
  void dispose() {
    _tradingLabController.dispose();
    _controller.dispose();
    _autoTradeController.dispose();
    _unattendedAutoTradeController.dispose();
    _journalController.dispose();
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

  Future<void> _reconcileJournalFromAccount() async {
    final snapshot = _autoTradeController.snapshot;
    if (snapshot == null) return;
    await _journalController.reconcileVerifiedExchangeClosures(
      pnlProjection: snapshot.authoritativePnl,
      openPositionIds: snapshot.positions
          .map((position) => position.positionId.trim())
          .where((positionId) => positionId.isNotEmpty)
          .toSet(),
    );
  }

  Future<void> _refreshCurrentDestination() async {
    switch (_destination) {
      case 5:
        final state = _autoTradeViewKey.currentState;
        if (state != null) {
          await state.refreshAll();
        } else {
          await _autoTradeController.reconcile(
            reason: PrivateAccountRefreshReason.manual,
            force: true,
          );
        }
        await _reconcileJournalFromAccount();
        return;
      case 6:
        await _controller.refresh();
        if (_autoTradeController.isConnected) {
          await _autoTradeController.reconcile(
            reason: PrivateAccountRefreshReason.manual,
            force: true,
          );
        }
        await _reconcileJournalFromAccount();
        await _journalController.refresh();
        return;
      default:
        await _controller.refresh();
        return;
    }
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
            journalController: _journalController,
            tradingLabController: _tradingLabController,
            destination: _destination,
            themeMode: widget.themeMode,
            locale: widget.locale,
            onToggleTheme: widget.onToggleTheme,
            onLocaleChanged: widget.onLocaleChanged,
            onOpenAnalysis: _openAnalysis,
            onAddSymbol: _showAddSymbolDialog,
            onOpenPortfolioRisk: widget.onOpenPortfolioRisk,
            onNavigate: (value) {
              setState(() => _destination = value);
              if (value == 4 || value == 5 || value == 6) {
                unawaited(_refreshCurrentDestination());
              }
            },
            showTopBar: desktop,
            realtimeMonitor: widget.realtimeMonitor,
            autoTradeViewKey: _autoTradeViewKey,
            onRefresh: _refreshCurrentDestination,
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
                    selectedIndex:
                        _desktopDestinationIndexes.contains(_destination)
                        ? _desktopDestinationIndexes.indexOf(_destination)
                        : 0,
                    onDestinationSelected: (value) {
                      setState(
                        () => _destination = _desktopDestinationIndexes[value],
                      );
                    },
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: _AlphaLogo(size: 44),
                    ),
                    destinations: _desktopDestinationIndexes
                        .map(
                          (index) => NavigationRailDestination(
                            icon: Icon(_destinations[index].icon),
                            selectedIcon: Icon(
                              _destinations[index].selectedIcon,
                            ),
                            label: Text(_destinationLabel(strings, index)),
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
            onRefresh: _refreshCurrentDestination,
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
                  : 0,
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
  final Future<void> Function() onRefresh;

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
          onPressed: controller.isLoading ? null : () => unawaited(onRefresh()),
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
  _Destination(Icons.home_outlined, Icons.home_rounded),
  _Destination(Icons.inbox_outlined, Icons.inbox_rounded),
  _Destination(
    Icons.candlestick_chart_outlined,
    Icons.candlestick_chart_rounded,
  ),
  _Destination(Icons.view_list_outlined, Icons.view_list_rounded),
  _Destination(Icons.science_outlined, Icons.science_rounded),
  _Destination(Icons.smart_toy_outlined, Icons.smart_toy_rounded),
  _Destination(Icons.menu_book_outlined, Icons.menu_book_rounded),
  _Destination(Icons.person_outline_rounded, Icons.person_rounded),
];
const _desktopDestinationIndexes = [0, 1, 2, 3, 5, 6, 7];
const _mobileDestinationIndexes = [0, 1, 5, 7];

String _destinationLabel(AppStrings strings, int index) => switch (index) {
  1 => strings.setups,
  2 => strings.analysis,
  3 => strings.watchlist,
  4 => strings.isPersian ? 'آزمایشگاه بات' : 'Bot Lab',
  5 => strings.isPersian ? 'ترید خودکار' : 'Auto Trade',
  6 => strings.isPersian ? 'ژورنال' : 'Journal',
  7 => strings.profile,
  _ => strings.t('خانه', 'Home'),
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
    required this.journalController,
    required this.tradingLabController,
    required this.destination,
    required this.themeMode,
    required this.locale,
    required this.onToggleTheme,
    required this.onLocaleChanged,
    required this.onOpenAnalysis,
    required this.onAddSymbol,
    required this.onOpenPortfolioRisk,
    required this.onNavigate,
    required this.showTopBar,
    required this.realtimeMonitor,
    required this.autoTradeViewKey,
    required this.onRefresh,
  });

  final OwnerAlphaController controller;
  final AutoTradeController autoTradeController;
  final UnattendedAutoTradeController unattendedAutoTradeController;
  final TradingJournalController journalController;
  final TradingLabController tradingLabController;
  final int destination;
  final ThemeMode themeMode;
  final Locale locale;
  final VoidCallback onToggleTheme;
  final ValueChanged<Locale> onLocaleChanged;
  final _OpenAnalysis onOpenAnalysis;
  final VoidCallback onAddSymbol;
  final VoidCallback onOpenPortfolioRisk;
  final ValueChanged<int> onNavigate;
  final bool showTopBar;
  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;
  final GlobalKey<_AutoTradeViewState> autoTradeViewKey;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final marketSnapshot = controller.snapshot;
    final journalLiveAnalyses = <String, TimeframeChartAnalysis>{
      for (final radar in marketSnapshot?.radar ?? const <SymbolRadarResult>[])
        for (final entry in radar.analysesByTimeframe.entries)
          '${radar.quote.symbol.trim().toUpperCase()}|${entry.key.trim()}':
              entry.value,
    };
    final journalLiveIdeas = <String, TradeIdea>{
      for (final radar in marketSnapshot?.radar ?? const <SymbolRadarResult>[])
        for (final entry in radar.ideasByTimeframe.entries)
          '${radar.quote.symbol.trim().toUpperCase()}|${entry.key.trim()}':
              entry.value,
    };
    final initialMarketLoading =
        controller.snapshot == null &&
        destination != 4 &&
        destination != 5 &&
        destination != 6 &&
        destination != 7;
    if (initialMarketLoading) {
      final horizontal = wide ? 28.0 : 16.0;
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          key: PageStorageKey('owner-alpha-$destination'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 0),
              sliver: SliverToBoxAdapter(
                child: Center(
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
                        _LiveBoundaryStrip(realtimeMonitor: realtimeMonitor),
                        if (controller.error != null) ...[
                          const SizedBox(height: 12),
                          _AlphaErrorStrip(
                            message: controller.error!,
                            stale: controller.hasStaleSnapshot,
                            onRetry: controller.refresh,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: _InitialLoading(controller: controller),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
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
                  if (destination != 5 && destination != 6 && destination != 7)
                    _LiveBoundaryStrip(realtimeMonitor: realtimeMonitor),
                  if (controller.error != null) ...[
                    const SizedBox(height: 12),
                    _AlphaErrorStrip(
                      message: controller.error!,
                      stale: controller.hasStaleSnapshot,
                      onRetry: controller.refresh,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (destination == 7)
                    _ProfileView(
                      controller: controller,
                      themeMode: themeMode,
                      locale: locale,
                      onToggleTheme: onToggleTheme,
                      onLocaleChanged: onLocaleChanged,
                    )
                  else if (destination == 6)
                    AnimatedBuilder(
                      animation: journalController,
                      builder: (context, _) => TradingJournalView(
                        locale: locale,
                        projections: journalController.projections,
                        statistics: journalController.statistics,
                        liveAnalyses: journalLiveAnalyses,
                        liveIdeas: journalLiveIdeas,
                        isLoading: journalController.isLoading,
                        error: journalController.error,
                      ),
                    )
                  else if (destination == 5)
                    _AutoTradeView(
                      key: autoTradeViewKey,
                      controller: autoTradeController,
                      unattendedController: unattendedAutoTradeController,
                      analysisController: controller,
                    )
                  else if (destination == 4)
                    _TradingLabView(
                      controller: tradingLabController,
                      marketController: controller,
                    )
                  else if (controller.snapshot == null)
                    _InitialLoading(controller: controller)
                  else
                    switch (destination) {
                      1 => _SignalInboxView(
                        controller: controller,
                        onOpenAnalysis: onOpenAnalysis,
                      ),
                      2 => _AlphaAnalysisView(
                        controller: controller,
                        snapshot: controller.snapshot!,
                      ),
                      3 => _WatchlistView(
                        controller: controller,
                        snapshot: controller.snapshot!,
                        onOpenAnalysis: onOpenAnalysis,
                        onAddSymbol: onAddSymbol,
                      ),
                      _ => _HomeDashboard(
                        controller: controller,
                        snapshot: controller.snapshot!,
                        onOpenAnalysis: onOpenAnalysis,
                        onNavigate: onNavigate,
                        onOpenPortfolioRisk: onOpenPortfolioRisk,
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
  const _LiveBoundaryStrip({required this.realtimeMonitor});

  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;

  @override
  Widget build(BuildContext context) {
    final monitor = realtimeMonitor;
    if (monitor == null) {
      return _buildContent(
        context,
        const RealtimeMarketMonitorSnapshot.initial(),
      );
    }
    return ValueListenableBuilder<RealtimeMarketMonitorSnapshot>(
      valueListenable: monitor,
      builder: (context, snapshot, _) => _buildContent(context, snapshot),
    );
  }

  Widget _buildContent(
    BuildContext context,
    RealtimeMarketMonitorSnapshot monitor,
  ) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final health = monitor.health;
    final operational = monitor.operational;
    final degraded = health?.degraded == true;
    final statusColor = operational
        ? degraded
              ? QuantaraColors.warning
              : QuantaraColors.success
        : QuantaraColors.cyan;
    final status = health == null
        ? strings.t('در حال آماده‌سازی', 'Preparing')
        : switch (health.state) {
            RealtimeMarketRuntimeState.live =>
              health.degraded
                  ? strings.t('پایش زنده محدود', 'Degraded live monitoring')
                  : strings.t('پایش زنده', 'Live monitoring'),
            RealtimeMarketRuntimeState.paused => strings.t(
              'پایش پیشنهادها در پس‌زمینه متوقف است',
              'Signal monitoring is paused in the background',
            ),
            RealtimeMarketRuntimeState.failed => strings.t(
              'خطای پایش',
              'Monitoring fault',
            ),
            RealtimeMarketRuntimeState.bootstrapping => strings.t(
              'دریافت تاریخچه',
              'Bootstrapping history',
            ),
            _ => strings.t('در حال اتصال', 'Connecting'),
          };
    final metrics = health == null
        ? strings.t(
            'داده عمومی Bitunix · بدون API Key · بدون سفارش واقعی',
            'Public Bitunix data · no API key · no real orders',
          )
        : strings.t(
            '${health.activeStreams}/${health.configuredStreams} جریان سالم · ${health.liveShards}/${health.activeShards} اتصال · تأخیر p95 شبکه ${health.p95TransportLag.inMilliseconds}ms · پردازش ${health.p95PipelineLatency.inMilliseconds}ms',
            '${health.activeStreams}/${health.configuredStreams} healthy streams · ${health.liveShards}/${health.activeShards} shards · p95 transport ${health.p95TransportLag.inMilliseconds}ms · processing ${health.p95PipelineLatency.inMilliseconds}ms',
          );
    final limitation = strings.t(
      'در این نسخه آزمایشی، پایش بلادرنگ فقط وقتی اپ یا تب باز است ادامه دارد.',
      'In this release candidate, realtime monitoring continues only while the app or tab is open.',
    );
    final error = monitor.error;
    final degradedDetail = health != null && health.quarantinedStreams > 0
        ? strings.t(
            '${health.quarantinedStreams} جریان به‌دلیل داده ناسالم قرنطینه شد؛ سایر نمادها فعال مانده‌اند.',
            '${health.quarantinedStreams} stream was quarantined for malformed data; healthy symbols remain active.',
          )
        : null;
    final detail = error ?? degradedDetail ?? limitation;
    return Semantics(
      container: true,
      label: '$status. $metrics. $detail',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                operational ? Icons.sensors_rounded : Icons.shield_outlined,
                color: statusColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metrics,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: error != null
                            ? scheme.error
                            : degradedDetail != null
                            ? QuantaraColors.warning
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
