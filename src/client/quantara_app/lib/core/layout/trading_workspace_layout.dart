import 'package:flutter/material.dart';

import '../theme/quantara_theme.dart';

abstract final class QuantaraBreakpoints {
  static const double tablet = 720;
  static const double desktop = 1180;
  static const double wideDesktop = 1440;
}

enum TradingWorkspacePane { market, chart, setup, positions }

final class TradingWorkspaceScaffold extends StatefulWidget {
  const TradingWorkspaceScaffold({
    required this.header,
    required this.marketPane,
    required this.chartPane,
    required this.setupPane,
    required this.positionsPane,
    this.initialMobilePane = TradingWorkspacePane.chart,
    super.key,
  });

  final Widget header;
  final Widget marketPane;
  final Widget chartPane;
  final Widget setupPane;
  final Widget positionsPane;
  final TradingWorkspacePane initialMobilePane;

  @override
  State<TradingWorkspaceScaffold> createState() =>
      _TradingWorkspaceScaffoldState();
}

class _TradingWorkspaceScaffoldState extends State<TradingWorkspaceScaffold> {
  late TradingWorkspacePane _mobilePane = widget.initialMobilePane;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= QuantaraBreakpoints.desktop) {
          return _desktop(width >= QuantaraBreakpoints.wideDesktop);
        }
        if (width >= QuantaraBreakpoints.tablet) {
          return _tablet();
        }
        return _mobile();
      },
    );
  }

  Widget _desktop(bool wide) {
    final gutter = wide ? 16.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        SizedBox(height: gutter),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: wide ? 280 : 240, child: widget.marketPane),
              SizedBox(width: gutter),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: widget.chartPane),
                    SizedBox(height: gutter),
                    SizedBox(
                      height: wide ? 260 : 220,
                      child: widget.positionsPane,
                    ),
                  ],
                ),
              ),
              SizedBox(width: gutter),
              SizedBox(width: wide ? 380 : 320, child: widget.setupPane),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tablet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 220, child: widget.marketPane),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: widget.chartPane),
                    const SizedBox(height: 12),
                    SizedBox(height: 210, child: widget.positionsPane),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 240, child: widget.setupPane),
      ],
    );
  }

  Widget _mobile() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final current = switch (_mobilePane) {
      TradingWorkspacePane.market => widget.marketPane,
      TradingWorkspacePane.chart => widget.chartPane,
      TradingWorkspacePane.setup => widget.setupPane,
      TradingWorkspacePane.positions => widget.positionsPane,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        const SizedBox(height: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(key: ValueKey(_mobilePane), child: current),
          ),
        ),
        NavigationBar(
          selectedIndex: TradingWorkspacePane.values.indexOf(_mobilePane),
          onDestinationSelected: (index) {
            setState(() => _mobilePane = TradingWorkspacePane.values[index]);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.view_list_outlined),
              selectedIcon: Icon(Icons.view_list_rounded),
              label: 'Market',
            ),
            NavigationDestination(
              icon: Icon(Icons.candlestick_chart_outlined),
              selectedIcon: Icon(Icons.candlestick_chart_rounded),
              label: 'Chart',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check_rounded),
              label: 'Setup',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Positions',
            ),
          ],
        ),
      ],
    );
  }
}

final class QuantaraCockpitHeader extends StatelessWidget {
  const QuantaraCockpitHeader({
    required this.title,
    required this.workspace,
    required this.modeLabel,
    required this.modeColor,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String workspace;
  final String modeLabel;
  final Color modeColor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const _QuantaraHeaderMark(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    workspace,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: modeColor.withValues(alpha: 0.13),
                border: Border.all(color: modeColor.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: modeColor),
                  const SizedBox(width: 6),
                  Text(
                    modeLabel,
                    style: TextStyle(
                      color: modeColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 6),
              ...actions,
            ],
          ],
        ),
      ),
    );
  }
}

class _QuantaraHeaderMark extends StatelessWidget {
  const _QuantaraHeaderMark();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [QuantaraColors.violet, QuantaraColors.cyan],
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.auto_graph_rounded,
          color: QuantaraColors.ink,
          size: 22,
        ),
      ),
    );
  }
}
