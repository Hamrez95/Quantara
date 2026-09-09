import '../../trading_journal/domain/trading_journal_models.dart';
import '../../trading_journal/domain/trading_journal_projection.dart';
import 'owner_alpha_models.dart';

enum SetupPerformanceRange { today, sevenDays, thirtyDays, all, custom }

enum SetupAnalyticalClassification { win, loss, breakeven, unavailable }

enum SetupActualEvidenceStatus {
  confirmedClosed,
  confirmedOpen,
  pendingReconciliation,
  unavailable,
  mismatch,
}

final class SetupPerformanceFilter {
  const SetupPerformanceFilter({
    this.range = SetupPerformanceRange.sevenDays,
    this.customStartUtc,
    this.customEndUtcExclusive,
    this.strategy,
    this.symbol,
    this.timeframe,
  });

  final SetupPerformanceRange range;
  final DateTime? customStartUtc;
  final DateTime? customEndUtcExclusive;
  final AnalysisStrategy? strategy;
  final String? symbol;
  final String? timeframe;

  SetupPerformanceFilter copyWith({
    SetupPerformanceRange? range,
    DateTime? customStartUtc,
    DateTime? customEndUtcExclusive,
    bool clearCustomRange = false,
    AnalysisStrategy? strategy,
    bool clearStrategy = false,
    String? symbol,
    bool clearSymbol = false,
    String? timeframe,
    bool clearTimeframe = false,
  }) => SetupPerformanceFilter(
    range: range ?? this.range,
    customStartUtc: clearCustomRange
        ? null
        : customStartUtc ?? this.customStartUtc,
    customEndUtcExclusive: clearCustomRange
        ? null
        : customEndUtcExclusive ?? this.customEndUtcExclusive,
    strategy: clearStrategy ? null : strategy ?? this.strategy,
    symbol: clearSymbol ? null : symbol ?? this.symbol,
    timeframe: clearTimeframe ? null : timeframe ?? this.timeframe,
  );

  bool includes(SignalJournalEntry entry, {required DateTime now}) {
    final resolvedAt = entry.resolvedAt?.toUtc();
    if (resolvedAt == null || !_hasVisibleAnalyticalResult(entry.outcome)) {
      return false;
    }
    if (strategy != null && entry.strategy != strategy) return false;
    final selectedSymbol = symbol?.trim().toUpperCase();
    if (selectedSymbol != null &&
        selectedSymbol.isNotEmpty &&
        entry.symbol.trim().toUpperCase() != selectedSymbol) {
      return false;
    }
    final selectedTimeframe = timeframe?.trim();
    if (selectedTimeframe != null &&
        selectedTimeframe.isNotEmpty &&
        entry.timeframe.trim() != selectedTimeframe) {
      return false;
    }

    final bounds = _rangeBounds(now);
    if (bounds == null) return true;
    if (bounds.start == null || bounds.endExclusive == null) return false;
    return !resolvedAt.isBefore(bounds.start!) &&
        resolvedAt.isBefore(bounds.endExclusive!);
  }

  _UtcBounds? _rangeBounds(DateTime now) {
    final utcNow = now.toUtc();
    switch (range) {
      case SetupPerformanceRange.all:
        return null;
      case SetupPerformanceRange.today:
        final localNow = now.toLocal();
        final localStart = DateTime(
          localNow.year,
          localNow.month,
          localNow.day,
        );
        return _UtcBounds(
          start: localStart.toUtc(),
          endExclusive: localStart.add(const Duration(days: 1)).toUtc(),
        );
      case SetupPerformanceRange.sevenDays:
        return _UtcBounds(
          start: utcNow.subtract(const Duration(days: 7)),
          endExclusive: utcNow.add(const Duration(microseconds: 1)),
        );
      case SetupPerformanceRange.thirtyDays:
        return _UtcBounds(
          start: utcNow.subtract(const Duration(days: 30)),
          endExclusive: utcNow.add(const Duration(microseconds: 1)),
        );
      case SetupPerformanceRange.custom:
        final start = customStartUtc?.toUtc();
        final end = customEndUtcExclusive?.toUtc();
        if (start == null || end == null || !start.isBefore(end)) {
          return const _UtcBounds(start: null, endExclusive: null);
        }
        return _UtcBounds(start: start, endExclusive: end);
    }
  }
}

final class SetupActualEvidence {
  const SetupActualEvidence({
    required this.status,
    this.journalTradeId,
    this.positionId,
    this.netRealizedPnl,
    this.grossRealizedPnl,
    this.fees,
    this.funding,
    this.unrealizedPnl,
    this.asOfUtc,
    this.provenance,
    this.warning,
  });

  final SetupActualEvidenceStatus status;
  final String? journalTradeId;
  final String? positionId;
  final double? netRealizedPnl;
  final double? grossRealizedPnl;
  final double? fees;
  final double? funding;
  final double? unrealizedPnl;
  final DateTime? asOfUtc;
  final String? provenance;
  final String? warning;

  bool get isConfirmedClosed =>
      status == SetupActualEvidenceStatus.confirmedClosed;
}

final class SetupPerformanceRow {
  const SetupPerformanceRow({
    required this.entry,
    required this.analyticalClassification,
    required this.actual,
    this.analyticalR,
  });

  final SignalJournalEntry entry;
  final SetupAnalyticalClassification analyticalClassification;
  final double? analyticalR;
  final SetupActualEvidence actual;

  double? get analyticalNetPnl {
    final value = entry.simulatedPnl;
    return value != null && value.isFinite ? value : null;
  }
}

final class SetupPerformanceSummary {
  const SetupPerformanceSummary({
    required this.resolvedCount,
    required this.analyticalWins,
    required this.analyticalLosses,
    required this.analyticalBreakeven,
    required this.analyticalUnavailable,
    required this.actualConfirmedClosedCount,
    required this.actualConfirmedOpenCount,
    required this.actualPendingCount,
    required this.actualMismatchCount,
    required this.actualUnavailableCount,
    this.analyticalWinRatePercent,
    this.totalAnalyticalR,
    this.averageAnalyticalR,
    this.totalSimulatedNetPnl,
    this.averageSimulatedNetPnl,
    this.actualNetRealizedPnl,
    this.actualWinRatePercent,
    this.actualFees,
    this.actualFunding,
  });

  final int resolvedCount;
  final int analyticalWins;
  final int analyticalLosses;
  final int analyticalBreakeven;
  final int analyticalUnavailable;
  final double? analyticalWinRatePercent;
  final double? totalAnalyticalR;
  final double? averageAnalyticalR;
  final double? totalSimulatedNetPnl;
  final double? averageSimulatedNetPnl;

  final int actualConfirmedClosedCount;
  final int actualConfirmedOpenCount;
  final int actualPendingCount;
  final int actualMismatchCount;
  final int actualUnavailableCount;
  final double? actualNetRealizedPnl;
  final double? actualWinRatePercent;
  final double? actualFees;
  final double? actualFunding;

  bool get hasAnalyticalEconomics => totalSimulatedNetPnl != null;
  bool get hasConfirmedActualEconomics => actualConfirmedClosedCount > 0;
}

final class SetupPerformanceReport {
  const SetupPerformanceReport({
    required this.generatedAtUtc,
    required this.filter,
    required this.rows,
    required this.summary,
  });

  final DateTime generatedAtUtc;
  final SetupPerformanceFilter filter;
  final List<SetupPerformanceRow> rows;
  final SetupPerformanceSummary summary;

  static SetupPerformanceReport build({
    required Iterable<SignalJournalEntry> signals,
    required Iterable<TradingJournalProjection> projections,
    required SetupPerformanceFilter filter,
    required DateTime now,
  }) {
    final filtered =
        signals
            .where((entry) => filter.includes(entry, now: now))
            .toList(growable: false)
          ..sort((a, b) {
            final left = a.resolvedAt ?? a.createdAt;
            final right = b.resolvedAt ?? b.createdAt;
            return right.compareTo(left);
          });

    final projectionsBySetup = <String, List<TradingJournalProjection>>{};
    for (final projection in projections) {
      final setupId = projection.plan?.setupId.trim() ?? '';
      if (setupId.isEmpty) continue;
      projectionsBySetup.putIfAbsent(setupId, () => []).add(projection);
    }

    final rows = filtered
        .map(
          (entry) => SetupPerformanceRow(
            entry: entry,
            analyticalClassification: _classifyAnalytical(entry),
            analyticalR: _analyticalR(entry),
            actual: _actualEvidence(
              entry,
              projectionsBySetup[entry.setupId] ?? const [],
            ),
          ),
        )
        .toList(growable: false);

    return SetupPerformanceReport(
      generatedAtUtc: now.toUtc(),
      filter: filter,
      rows: List.unmodifiable(rows),
      summary: _summarize(rows),
    );
  }

  String toCsv() {
    const headers = [
      'setup_id',
      'resolved_at_utc',
      'symbol',
      'timeframe',
      'direction',
      'strategy',
      'analytical_outcome',
      'analytical_classification',
      'analytical_net_pnl_simulated',
      'analytical_r',
      'analytical_provenance',
      'actual_status',
      'actual_journal_trade_id',
      'actual_position_id',
      'actual_net_realized_pnl',
      'actual_gross_realized_pnl',
      'actual_fees',
      'actual_funding',
      'actual_unrealized_pnl',
      'actual_as_of_utc',
      'actual_provenance',
      'actual_warning',
    ];
    final buffer = StringBuffer()..writeln(headers.join(','));
    for (final row in rows) {
      final entry = row.entry;
      final actual = row.actual;
      buffer.writeln(
        [
          entry.setupId,
          entry.resolvedAt?.toUtc().toIso8601String(),
          entry.symbol,
          entry.timeframe,
          entry.direction.name,
          entry.strategy.name,
          entry.outcome.name,
          row.analyticalClassification.name,
          row.analyticalNetPnl,
          row.analyticalR,
          'closed_candle_replay_after_defined_costs',
          actual.status.name,
          actual.journalTradeId,
          actual.positionId,
          actual.netRealizedPnl,
          actual.grossRealizedPnl,
          actual.fees,
          actual.funding,
          actual.unrealizedPnl,
          actual.asOfUtc?.toUtc().toIso8601String(),
          actual.provenance,
          actual.warning,
        ].map(_csv).join(','),
      );
    }
    return buffer.toString();
  }
}

final class _UtcBounds {
  const _UtcBounds({required this.start, required this.endExclusive});

  final DateTime? start;
  final DateTime? endExclusive;
}

bool _hasVisibleAnalyticalResult(SignalOutcome outcome) =>
    outcome == SignalOutcome.stopped ||
    outcome == SignalOutcome.tp1 ||
    outcome == SignalOutcome.tp2 ||
    outcome == SignalOutcome.tp3;

SetupAnalyticalClassification _classifyAnalytical(SignalJournalEntry entry) {
  final pnl = entry.simulatedPnl;
  if (pnl == null || !pnl.isFinite) {
    return SetupAnalyticalClassification.unavailable;
  }
  if (pnl > 0.00000001) return SetupAnalyticalClassification.win;
  if (pnl < -0.00000001) return SetupAnalyticalClassification.loss;
  return SetupAnalyticalClassification.breakeven;
}

double? _analyticalR(SignalJournalEntry entry) {
  final pnl = entry.simulatedPnl;
  final risk = entry.maximumLoss;
  if (pnl == null || !pnl.isFinite || !risk.isFinite || risk <= 0) {
    return null;
  }
  final value = pnl / risk;
  return value.isFinite ? value : null;
}

SetupActualEvidence _actualEvidence(
  SignalJournalEntry entry,
  List<TradingJournalProjection> matches,
) {
  if (matches.isEmpty) {
    return const SetupActualEvidence(
      status: SetupActualEvidenceStatus.unavailable,
      warning: 'No journal trade is linked to this setup.',
    );
  }
  if (matches.length != 1) {
    return const SetupActualEvidence(
      status: SetupActualEvidenceStatus.mismatch,
      warning: 'Multiple journal trades map to the same setup.',
    );
  }

  final projection = matches.single;
  final exchangeEvents = projection.timeline
      .where((event) => event.source == TradingJournalFactSource.exchange)
      .toList(growable: false);
  DateTime? asOf;
  for (final event in exchangeEvents) {
    final eventAsOf = event.asOf.toUtc();
    if (asOf == null || eventAsOf.isAfter(asOf)) asOf = eventAsOf;
  }
  final hasUnsafeFacts =
      projection.integrity == TradingJournalIntegrity.unverified ||
      exchangeEvents.any(
        (event) =>
            event.quality == TradingJournalFactQuality.stale ||
            event.quality == TradingJournalFactQuality.unverified,
      );
  if (hasUnsafeFacts) {
    return SetupActualEvidence(
      status: SetupActualEvidenceStatus.pendingReconciliation,
      journalTradeId: projection.journalTradeId,
      positionId: projection.positionId,
      asOfUtc: asOf,
      provenance: 'exchange_reconciliation',
      warning: 'Exchange evidence is stale or unverified.',
    );
  }

  final confirmedExchangeEvents = exchangeEvents
      .where((event) => event.quality == TradingJournalFactQuality.confirmed)
      .toList(growable: false);
  if (confirmedExchangeEvents.isEmpty) {
    return SetupActualEvidence(
      status: SetupActualEvidenceStatus.pendingReconciliation,
      journalTradeId: projection.journalTradeId,
      positionId: projection.positionId,
      warning:
          'The setup is linked, but confirmed exchange evidence is absent.',
    );
  }

  double? unrealized;
  for (final event in confirmedExchangeEvents.reversed) {
    final raw = event.details['unrealizedPnl'];
    if (raw is num && raw.toDouble().isFinite) {
      unrealized = raw.toDouble();
      break;
    }
  }

  if (projection.state == TradingJournalTradeState.open) {
    return SetupActualEvidence(
      status: SetupActualEvidenceStatus.confirmedOpen,
      journalTradeId: projection.journalTradeId,
      positionId: projection.positionId,
      unrealizedPnl: unrealized,
      asOfUtc: asOf,
      provenance: 'confirmed_exchange_open_position',
      warning: 'Open PnL is not included in realized performance.',
    );
  }

  if (projection.state != TradingJournalTradeState.closed ||
      projection.economicsPending ||
      projection.netPnl == null ||
      !projection.netPnl!.isFinite ||
      projection.grossPnl == null ||
      !projection.grossPnl!.isFinite ||
      projection.fees == null ||
      !projection.fees!.isFinite ||
      projection.funding == null ||
      !projection.funding!.isFinite) {
    return SetupActualEvidence(
      status: SetupActualEvidenceStatus.pendingReconciliation,
      journalTradeId: projection.journalTradeId,
      positionId: projection.positionId,
      asOfUtc: asOf,
      provenance: 'exchange_reconciliation',
      warning: projection.economicsPending
          ? 'Position closed, but exchange economics are pending.'
          : 'Complete reconciled close economics are unavailable.',
    );
  }

  final confirmedClose = confirmedExchangeEvents.any(
    (event) =>
        (event.type == TradingJournalEventType.positionClosed ||
            event.type == TradingJournalEventType.liquidation) &&
        event.details['economicsPending'] != true,
  );
  if (!confirmedClose) {
    return SetupActualEvidence(
      status: SetupActualEvidenceStatus.pendingReconciliation,
      journalTradeId: projection.journalTradeId,
      positionId: projection.positionId,
      asOfUtc: asOf,
      provenance: 'exchange_reconciliation',
      warning: 'A confirmed exchange close event is missing.',
    );
  }

  return SetupActualEvidence(
    status: SetupActualEvidenceStatus.confirmedClosed,
    journalTradeId: projection.journalTradeId,
    positionId: projection.positionId,
    netRealizedPnl: projection.netPnl,
    grossRealizedPnl: projection.grossPnl,
    fees: projection.fees,
    funding: projection.funding,
    asOfUtc: asOf,
    provenance: 'confirmed_exchange_reconciliation',
  );
}

SetupPerformanceSummary _summarize(List<SetupPerformanceRow> rows) {
  var analyticalWins = 0;
  var analyticalLosses = 0;
  var analyticalBreakeven = 0;
  var analyticalUnavailable = 0;
  final analyticalR = <double>[];
  final simulatedPnl = <double>[];

  var actualClosed = 0;
  var actualOpen = 0;
  var actualPending = 0;
  var actualMismatch = 0;
  var actualUnavailable = 0;
  var actualWins = 0;
  var actualLosses = 0;
  final actualNet = <double>[];
  final actualFees = <double>[];
  final actualFunding = <double>[];

  for (final row in rows) {
    switch (row.analyticalClassification) {
      case SetupAnalyticalClassification.win:
        analyticalWins++;
      case SetupAnalyticalClassification.loss:
        analyticalLosses++;
      case SetupAnalyticalClassification.breakeven:
        analyticalBreakeven++;
      case SetupAnalyticalClassification.unavailable:
        analyticalUnavailable++;
    }
    if (row.analyticalR case final value?) analyticalR.add(value);
    if (row.analyticalNetPnl case final value?) simulatedPnl.add(value);

    final actual = row.actual;
    switch (actual.status) {
      case SetupActualEvidenceStatus.confirmedClosed:
        actualClosed++;
        final net = actual.netRealizedPnl;
        if (net != null) {
          actualNet.add(net);
          if (net > 0.00000001) actualWins++;
          if (net < -0.00000001) actualLosses++;
        }
        if (actual.fees case final value?) actualFees.add(value);
        if (actual.funding case final value?) actualFunding.add(value);
      case SetupActualEvidenceStatus.confirmedOpen:
        actualOpen++;
      case SetupActualEvidenceStatus.pendingReconciliation:
        actualPending++;
      case SetupActualEvidenceStatus.mismatch:
        actualMismatch++;
      case SetupActualEvidenceStatus.unavailable:
        actualUnavailable++;
    }
  }

  final analyticalWinDenominator = analyticalWins + analyticalLosses;
  final actualWinDenominator = actualWins + actualLosses;
  return SetupPerformanceSummary(
    resolvedCount: rows.length,
    analyticalWins: analyticalWins,
    analyticalLosses: analyticalLosses,
    analyticalBreakeven: analyticalBreakeven,
    analyticalUnavailable: analyticalUnavailable,
    analyticalWinRatePercent: analyticalWinDenominator == 0
        ? null
        : analyticalWins / analyticalWinDenominator * 100,
    totalAnalyticalR: _sumOrNull(analyticalR),
    averageAnalyticalR: _averageOrNull(analyticalR),
    totalSimulatedNetPnl: _sumOrNull(simulatedPnl),
    averageSimulatedNetPnl: _averageOrNull(simulatedPnl),
    actualConfirmedClosedCount: actualClosed,
    actualConfirmedOpenCount: actualOpen,
    actualPendingCount: actualPending,
    actualMismatchCount: actualMismatch,
    actualUnavailableCount: actualUnavailable,
    actualNetRealizedPnl: _sumOrNull(actualNet),
    actualWinRatePercent: actualWinDenominator == 0
        ? null
        : actualWins / actualWinDenominator * 100,
    actualFees: _sumOrNull(actualFees),
    actualFunding: _sumOrNull(actualFunding),
  );
}

double? _sumOrNull(List<double> values) =>
    values.isEmpty ? null : values.fold<double>(0, (sum, value) => sum + value);

double? _averageOrNull(List<double> values) {
  final total = _sumOrNull(values);
  return total == null ? null : total / values.length;
}

String _csv(Object? value) {
  if (value == null) return '';
  final text = value.toString();
  if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) {
    return text;
  }
  return '"${text.replaceAll('"', '""')}"';
}
