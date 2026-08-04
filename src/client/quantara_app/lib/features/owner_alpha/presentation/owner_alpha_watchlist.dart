part of 'owner_alpha_page.dart';

class _WatchlistView extends StatelessWidget {
  const _WatchlistView({
    required this.controller,
    required this.snapshot,
    required this.onOpenAnalysis,
    required this.onAddSymbol,
  });

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;
  final ValueChanged<String> onOpenAnalysis;
  final VoidCallback onAddSymbol;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final positive = snapshot.radar
        .where((item) => item.quote.changePercent >= 0)
        .length;
    final actionable = snapshot.radar
        .where((item) => item.idea.isActionable)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WatchlistHero(
          tracked: snapshot.radar.length,
          positive: positive,
          actionable: actionable,
          onAddSymbol: controller.isLoading ? null : onAddSymbol,
        ),
        const SizedBox(height: 16),
        SectionCard(
          accentColor: QuantaraColors.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: strings.t('تایم‌فریم واچ‌لیست', 'Watchlist timeframe'),
                subtitle: strings.t(
                  'انتخاب تایم‌فریم، تحلیل و جهت همه نمادها را با داده واقعی تازه می‌کند.',
                  'Selecting a timeframe refreshes every symbol with real market analysis.',
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final timeframe
                        in OwnerAlphaController.timeframes) ...[
                      ChoiceChip(
                        selected: controller.selectedTimeframe == timeframe,
                        showCheckmark: false,
                        avatar: Icon(
                          controller.selectedTimeframe == timeframe
                              ? Icons.query_stats_rounded
                              : Icons.schedule_rounded,
                          size: 17,
                        ),
                        label: Text(
                          timeframe,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        onSelected: controller.isLoading
                            ? null
                            : (_) => controller.selectTimeframe(timeframe),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionHeading(
          title: strings.myWatchlist,
          subtitle: strings.t(
            'قیمت، جهت، قدرت ساختار و نمودار کوتاه هر نماد',
            'Price, direction, structure strength and compact chart for each symbol',
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < snapshot.radar.length; index++) ...[
          _WatchlistMarketCard(
            result: snapshot.radar[index],
            canRemove: snapshot.radar.length > 1,
            onOpen: () => onOpenAnalysis(snapshot.radar[index].quote.symbol),
            onRemove: () =>
                controller.removeSymbol(snapshot.radar[index].quote.symbol),
          ),
          if (index != snapshot.radar.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _WatchlistHero extends StatelessWidget {
  const _WatchlistHero({
    required this.tracked,
    required this.positive,
    required this.actionable,
    required this.onAddSymbol,
  });

  final int tracked;
  final int positive;
  final int actionable;
  final VoidCallback? onAddSymbol;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: strings.myWatchlist,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(QuantaraRadius.large),
          border: Border.all(
            color: QuantaraColors.electricBlue.withValues(alpha: 0.3),
          ),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              Color.alphaBlend(
                QuantaraColors.electricBlue.withValues(alpha: 0.18),
                scheme.surface,
              ),
              Color.alphaBlend(
                QuantaraColors.violet.withValues(alpha: 0.12),
                scheme.surface,
              ),
              scheme.surface,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: QuantaraColors.electricBlue.withValues(alpha: 0.1),
              blurRadius: 32,
              spreadRadius: -18,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -70,
              end: -60,
              child: IgnorePointer(
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        QuantaraColors.cyan.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 560;
                      final title = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: QuantaraColors.premiumGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: QuantaraColors.cyan.withValues(
                                    alpha: 0.18,
                                  ),
                                  blurRadius: 18,
                                  spreadRadius: -8,
                                ),
                              ],
                            ),
                            child: const SizedBox.square(
                              dimension: 50,
                              child: Icon(
                                Icons.visibility_rounded,
                                color: QuantaraColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.myWatchlist,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  strings.t(
                                    'دید کامل بازار با قیمت واقعی و تحلیل چندتایم‌فریمی',
                                    'A complete market view with real prices and multi-timeframe analysis',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final add = FilledButton.tonalIcon(
                        onPressed: onAddSymbol,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(strings.add),
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            title,
                            const SizedBox(height: 14),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: add,
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 16),
                          add,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 680 ? 3 : 1;
                      const gap = 10.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      final metrics = [
                        (
                          strings.t('نمادهای پایش', 'Tracked symbols'),
                          '$tracked',
                          Icons.layers_outlined,
                          QuantaraColors.electricBlue,
                        ),
                        (
                          strings.t('بازده مثبت ۲۴ساعته', 'Positive 24h'),
                          '$positive/$tracked',
                          Icons.trending_up_rounded,
                          QuantaraColors.success,
                        ),
                        (
                          strings.t('ستاپ قابل اقدام', 'Actionable setups'),
                          '$actionable',
                          Icons.bolt_rounded,
                          actionable > 0
                              ? QuantaraColors.violet
                              : QuantaraColors.warning,
                        ),
                      ];
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width: width,
                              child: FinanceMetricPanel(
                                label: metric.$1,
                                value: metric.$2,
                                icon: metric.$3,
                                color: metric.$4,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistMarketCard extends StatelessWidget {
  const _WatchlistMarketCard({
    required this.result,
    required this.canRemove,
    required this.onOpen,
    required this.onRemove,
  });

  final SymbolRadarResult result;
  final bool canRemove;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final quote = result.quote;
    final analysis = result.analysis;
    final changeColor = quote.changePercent >= 0
        ? QuantaraColors.success
        : QuantaraColors.danger;
    final directionColor = _chartDirectionColor(analysis.direction);
    final candles = analysis.candles;
    final start = math.max(0, candles.length - 32);
    final sparkline = candles
        .sublist(start)
        .map((candle) => candle.close)
        .toList(growable: false);

    return SectionCard(
      accentColor: directionColor,
      semanticLabel: '${quote.symbol} ${quote.lastPrice}',
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 540;
              final identity = Row(
                children: [
                  SymbolAvatar(symbol: quote.symbol, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quote.symbol,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${quote.displayName} · ${analysis.timeframe}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final quoteBlock = Column(
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    QuantaraNumberFormat.marketValue(quote.lastPrice),
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    QuantaraNumberFormat.marketPercent(quote.changePercent),
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: changeColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [identity, const SizedBox(height: 12), quoteBlock],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  quoteBlock,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          SparklineChart(values: sparkline, color: changeColor, height: 58),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: _directionLabel(context, analysis.direction),
                color: directionColor,
                icon: analysis.direction == ChartDirection.bullish
                    ? Icons.north_east_rounded
                    : analysis.direction == ChartDirection.bearish
                    ? Icons.south_east_rounded
                    : Icons.east_rounded,
              ),
              StatusPill(
                label: strings.t(
                  'قدرت ${(analysis.directionStrength * 100).round()}٪',
                  '${(analysis.directionStrength * 100).round()}% strength',
                ),
                color: QuantaraColors.cyan,
                icon: Icons.speed_rounded,
              ),
              StatusPill(
                label: strings.t(
                  '${analysis.zones.length} ناحیه قیمتی',
                  '${analysis.zones.length} price zones',
                ),
                color: QuantaraColors.violet,
                icon: Icons.layers_outlined,
              ),
              if (result.idea.isActionable)
                StatusPill(
                  label: strings.t(
                    'امتیاز ${result.idea.confidencePercent}',
                    'Score ${result.idea.confidencePercent}',
                  ),
                  color: _ideaColor(context, result.idea.direction),
                  icon: Icons.bolt_rounded,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.candlestick_chart_rounded),
                  label: Text(strings.t('مشاهده تحلیل', 'View analysis')),
                ),
              ),
              if (canRemove)
                PopupMenuButton<_WatchlistAction>(
                  tooltip: strings.removeSymbol(quote.symbol),
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (action) {
                    if (action == _WatchlistAction.remove) onRemove();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _WatchlistAction.remove,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: QuantaraSpacing.xs),
                          Text(strings.removeSymbol(quote.symbol)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _WatchlistAction { remove }
