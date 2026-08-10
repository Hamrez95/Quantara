part of 'owner_alpha_page.dart';

class _TradingLabInsights extends StatelessWidget {
  const _TradingLabInsights({required this.run, required this.history});

  final TradingLabRun run;
  final List<TradingLabRun> history;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final metrics = calculateTradingLabMetrics(
      run,
      evidenceAtUtc: run.lastSnapshotAtUtc ?? run.manifest.startedAtUtc,
    );
    final scorecards = buildTradingLabStrategyScorecards(run);
    final comparable = history
        .where((item) => item.manifest.runId != run.manifest.runId)
        .toList(growable: false);
    final comparison = comparable.isEmpty
        ? null
        : compareTradingLabRuns(
            comparable.first,
            run,
            evidenceAtUtc: run.lastSnapshotAtUtc ?? run.manifest.startedAtUtc,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TradingLabDetailedMetricsCard(metrics: metrics),
        const SizedBox(height: 16),
        _TradingLabStrategyScorecardCard(scorecards: scorecards),
        if (comparison != null) ...[
          const SizedBox(height: 16),
          _TradingLabComparisonCard(comparison: comparison, fa: fa),
        ],
        if (run.openPositions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _TradingLabPlanOverlaysCard(positions: run.openPositions),
        ],
      ],
    );
  }
}

class _TradingLabDetailedMetricsCard extends StatelessWidget {
  const _TradingLabDetailedMetricsCard({required this.metrics});

  final TradingLabMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final pf = metrics.profitFactor;
    final payoff = metrics.payoffRatio;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'متریک‌های کامل آزمایش' : 'Complete experiment metrics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fa
                ? 'یک منبع عددی مشترک برای UI، Compare Runs و خروجی AI.'
                : 'One numeric source of truth for UI, Compare Runs and AI export.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _labMetric(fa ? 'PnL خالص' : 'Net PnL', metrics.netPnl, suffix: ' USDT'),
              _labMetric(fa ? 'PnL تحقق‌یافته' : 'Realized PnL', metrics.realizedPnl, suffix: ' USDT'),
              _labMetric(fa ? 'PnL باز' : 'Unrealized PnL', metrics.unrealizedPnl, suffix: ' USDT'),
              _labMetric(fa ? 'کارمزد' : 'Fees', metrics.totalFees, suffix: ' USDT'),
              _labMetric('Funding', metrics.totalFunding, suffix: ' USDT'),
              _labMetric('Slippage', metrics.totalSlippage, suffix: ' USDT'),
              MetricTile(
                label: fa ? 'مدت Max DD' : 'Max DD duration',
                value: _labDuration(metrics.maximumDrawdownDurationSeconds),
              ),
              MetricTile(
                label: fa ? 'برد/باخت/سر‌به‌سر' : 'W/L/BE',
                value: '${metrics.wins}/${metrics.losses}/${metrics.breakevens}',
              ),
              MetricTile(
                label: 'Profit Factor',
                value: pf == null ? '—' : (pf.isFinite ? pf.toStringAsFixed(2) : '∞'),
              ),
              _labMetric('Expectancy', metrics.expectancyUsdt, suffix: ' USDT'),
              _labMetric('Expectancy R', metrics.expectancyR),
              _labMetric(fa ? 'Median R' : 'Median R', metrics.medianR),
              _labMetric(fa ? 'میانگین برد' : 'Avg winner', metrics.averageWinner, suffix: ' USDT'),
              _labMetric(fa ? 'میانگین باخت' : 'Avg loser', metrics.averageLoser, suffix: ' USDT'),
              MetricTile(
                label: fa ? 'Payoff' : 'Payoff ratio',
                value: payoff?.toStringAsFixed(2) ?? '—',
              ),
              _labMetric(fa ? 'بهترین معامله' : 'Best trade', metrics.bestTrade, suffix: ' USDT'),
              _labMetric(fa ? 'بدترین معامله' : 'Worst trade', metrics.worstTrade, suffix: ' USDT'),
              MetricTile(
                label: fa ? 'میانگین زمان معامله' : 'Avg holding',
                value: _labDuration(metrics.averageHoldingSeconds.round()),
              ),
              MetricTile(
                label: fa ? 'بیشترین برد متوالی' : 'Max win streak',
                value: '${metrics.maximumConsecutiveWins}',
              ),
              MetricTile(
                label: fa ? 'بیشترین باخت متوالی' : 'Max loss streak',
                value: '${metrics.maximumConsecutiveLosses}',
              ),
              _labMetric(fa ? 'زمان در بازار' : 'Exposure', metrics.exposurePercent, suffix: '%'),
              _labMetric(fa ? 'استفاده از Slot' : 'Slot utilization', metrics.positionSlotUtilizationPercent, suffix: '%'),
              _labMetric('MFE avg', metrics.averageMfeR, suffix: 'R'),
              _labMetric('MAE avg', metrics.averageMaeR, suffix: 'R'),
              MetricTile(
                label: fa ? 'تبدیل سیگنال به ورود' : 'Signal → entry',
                value: '${metrics.signalToEntryConversionPercent.toStringAsFixed(1)}%',
              ),
              MetricTile(
                label: 'SL / TP1+ / TP2+ / TP3',
                value: '${metrics.stopOutCount}/${metrics.tp1OrBetterCount}/${metrics.tp2OrBetterCount}/${metrics.tp3Count}',
              ),
            ],
          ),
          if (metrics.rejectionsByReason.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics.rejectionsByReason.entries
                  .map(
                    (entry) => Chip(
                      label: Text('${entry.key}: ${entry.value}'),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (metrics.sampleWarning != null) ...[
            const SizedBox(height: 12),
            Text(
              metrics.sampleWarning!,
              style: const TextStyle(
                color: QuantaraColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _labMetric(String label, double value, {String suffix = ''}) => MetricTile(
    label: label,
    value: '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}$suffix',
    valueColor: value >= 0 ? QuantaraColors.success : QuantaraColors.danger,
  );
}

class _TradingLabStrategyScorecardCard extends StatelessWidget {
  const _TradingLabStrategyScorecardCard({required this.scorecards});

  final List<TradingLabStrategyScorecard> scorecards;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Strategy Scorecard',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fa
                ? 'تفکیک بر اساس Strategy/Version، نماد، تایم‌فریم، Regime، جهت، Confidence و RR.'
                : 'Segmented by strategy/version, symbol, timeframe, regime, direction, confidence and RR.',
          ),
          const SizedBox(height: 12),
          if (scorecards.isEmpty)
            Text(
              fa
                  ? 'هنوز معامله بسته کافی برای Scorecard نداریم؛ Shadow Evidence همچنان در ZIP ثبت می‌شود.'
                  : 'No closed paper trade yet; Shadow Evidence is still collected in the ZIP.',
            )
          else
            for (final item in scorecards.take(16)) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.strategyVersion} · ${item.symbol} · ${item.timeframe}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.marketRegime} · ${item.direction} · C ${item.confidenceBucket} · RR ${item.riskRewardBucket}',
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'n=${item.sampleSize}\n${item.winRatePercent.toStringAsFixed(0)}% · ${item.averageR.toStringAsFixed(2)}R',
                      textAlign: TextAlign.end,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: item.averageR >= 0
                            ? QuantaraColors.success
                            : QuantaraColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _TradingLabComparisonCard extends StatelessWidget {
  const _TradingLabComparisonCard({required this.comparison, required this.fa});

  final Map<String, Object?> comparison;
  final bool fa;

  @override
  Widget build(BuildContext context) {
    final delta = (comparison['delta'] as Map<Object?, Object?>?) ?? const {};
    final guard = (comparison['promotionGuard'] as Map<Object?, Object?>?) ?? const {};
    double d(String key) => (delta[key] as num?)?.toDouble() ?? 0;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'Champion vs Candidate' : 'Champion vs Candidate',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${comparison['championRunId']}  →  ${comparison['candidateRunId']}',
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _deltaTile('Δ Return', d('returnPercent'), '%'),
              _deltaTile('Δ Max DD', d('maximumDrawdownPercent'), '%', lowerIsBetter: true),
              _deltaTile('Δ Expectancy', d('expectancyUsdt'), ' USDT'),
              _deltaTile('Δ Avg R', d('averageR'), 'R'),
              _deltaTile('Δ Win rate', d('winRatePercent'), '%'),
              _deltaTile('Δ Slot use', d('positionSlotUtilizationPercent'), '%'),
            ],
          ),
          if (guard['warning'] != null) ...[
            const SizedBox(height: 12),
            Text(
              guard['warning'].toString(),
              style: const TextStyle(
                color: QuantaraColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deltaTile(
    String label,
    double value,
    String suffix, {
    bool lowerIsBetter = false,
  }) {
    final favorable = lowerIsBetter ? value <= 0 : value >= 0;
    return MetricTile(
      label: label,
      value: '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}$suffix',
      valueColor: favorable ? QuantaraColors.success : QuantaraColors.danger,
    );
  }
}

class _TradingLabPlanOverlaysCard extends StatelessWidget {
  const _TradingLabPlanOverlaysCard({required this.positions});

  final List<TradingLabPosition> positions;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'Overlay پلن پوزیشن' : 'Position plan overlays',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (final position in positions) ...[
            Text(
              '${position.symbol} · ${position.timeframe}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            _TradingLabPricePlan(position: position),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _TradingLabPricePlan extends StatelessWidget {
  const _TradingLabPricePlan({required this.position});
  final TradingLabPosition position;

  @override
  Widget build(BuildContext context) {
    final levels = <({String label, double price, Color color})>[
      (label: 'SL', price: position.currentStopLoss, color: QuantaraColors.danger),
      (label: 'ENTRY', price: position.entryPrice, color: QuantaraColors.cyan),
      for (var index = 0; index < position.targets.length; index++)
        (
          label: 'TP${index + 1}',
          price: position.targets[index],
          color: QuantaraColors.success,
        ),
    ]..sort((a, b) => b.price.compareTo(a.price));
    final high = levels.first.price;
    final low = levels.last.price;
    final range = math.max(1e-12, high - low);
    return SizedBox(
      height: 132,
      child: Stack(
        children: [
          for (final level in levels)
            Positioned(
              top: (high - level.price) / range * 100 + 8,
              left: 0,
              right: 0,
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      level.label,
                      style: TextStyle(
                        color: level.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(height: 1.5, color: level.color.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    QuantaraNumberFormat.marketValue(level.price),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _labDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(1)}m';
  if (seconds < 86400) return '${(seconds / 3600).toStringAsFixed(1)}h';
  return '${(seconds / 86400).toStringAsFixed(1)}d';
}
