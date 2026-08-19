import 'dart:math' as math;

import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../../portfolio_risk/data/portfolio_risk_ledger_store.dart';
import '../../portfolio_risk/domain/capital_guardian.dart';

const localLivePortfolioRiskLedgerRecordKey =
    'local-live-portfolio-risk-ledger-v1';
const _localLiveCapitalEquityRecordKey =
    'local-live-capital-equity-high-watermark-v1';

final class LocalLiveCapitalGuardianSnapshot {
  const LocalLiveCapitalGuardianSnapshot({
    required this.currentEquity,
    required this.peakEquity,
    required this.drawdownFraction,
    required this.drawdownTier,
    required this.riskMultiplier,
    required this.riskLimit,
    required this.openRisk,
    required this.remainingRisk,
    required this.asOf,
  });

  final double currentEquity;
  final double peakEquity;
  final double drawdownFraction;
  final CapitalGuardianDrawdownTier drawdownTier;
  final double riskMultiplier;
  final double riskLimit;
  final double openRisk;
  final double remainingRisk;
  final DateTime asOf;
}

/// Maintains the Local Live account-equity high-water mark and projects that
/// exchange-derived truth into the durable Capital Guardian state.
///
/// The high-water mark is intentionally monotonic and independent from an app
/// session. Restarting Local Live therefore cannot erase an existing drawdown.
/// External withdrawals may conservatively look like drawdown; that is safer
/// than silently resetting protection and can be reconciled explicitly later.
final class LocalLiveCapitalGuardianMonitor {
  LocalLiveCapitalGuardianMonitor({
    Future<QuantaraDurableDatabase> Function()? databaseFactory,
    DatabasePortfolioRiskLedgerStore? riskStore,
  }) : _databaseFactory =
           databaseFactory ?? (() => QuantaraDatabaseProvider.instance),
       _riskStore =
           riskStore ??
           DatabasePortfolioRiskLedgerStore(
             databaseFactory: databaseFactory,
             recordKey: localLivePortfolioRiskLedgerRecordKey,
           );

  final Future<QuantaraDurableDatabase> Function() _databaseFactory;
  final DatabasePortfolioRiskLedgerStore _riskStore;
  static const CapitalGuardianPolicy _policy = CapitalGuardianPolicy();

  Future<LocalLiveCapitalGuardianSnapshot> refresh({
    required double accountEquity,
    required DateTime now,
    bool abnormalVolatility = false,
  }) async {
    if (!accountEquity.isFinite || accountEquity <= 0) {
      throw const FormatException(
        'Live account equity is invalid; Capital Guardian cannot be refreshed.',
      );
    }
    final timestamp = now.toUtc();
    final equityTruth = await _recordEquity(
      accountEquity: accountEquity,
      now: timestamp,
    );

    return _riskStore
        .mutateRiskAndGuardian<LocalLiveCapitalGuardianSnapshot>((
          ledger,
          guardian,
        ) async {
          if (ledger == null) {
            throw StateError(
              'Capital Guardian cannot update before the Local Live risk ledger exists.',
            );
          }
          final base =
              guardian ??
              CapitalGuardianState.initial(
                now: timestamp,
                timezoneOffsetMinutes:
                    ledger.tradingDay.timezoneOffsetMinutes,
              );
          final next = base.recordEnvironment(
            drawdownFraction: equityTruth.drawdownFraction,
            abnormalVolatility: abnormalVolatility,
            now: timestamp,
            timezoneOffsetMinutes: ledger.tradingDay.timezoneOffsetMinutes,
            policy: _policy,
          );
          final snapshot = _snapshot(
            equity: equityTruth,
            guardian: next,
            riskLimit: ledger.dailyRisk.limit,
            openRisk: ledger.dailyRisk.openRisk,
            remainingRisk: ledger.dailyRisk.available,
          );
          return PortfolioRiskAndGuardianMutation<
            LocalLiveCapitalGuardianSnapshot
          >(value: snapshot, nextGuardian: next);
        });
  }

  Future<LocalLiveCapitalGuardianSnapshot?> load() async {
    final database = await _databaseFactory();
    final equityRecord = await database.read(
      QuantaraDurableCategory.managedPositions,
      _localLiveCapitalEquityRecordKey,
    );
    final ledger = await _riskStore.load();
    final guardian = await _riskStore.loadCapitalGuardian();
    if (equityRecord == null || ledger == null || guardian == null) return null;

    final equity = _EquityTruth.fromRecord(equityRecord);
    if ((guardian.drawdownFraction - equity.drawdownFraction).abs() > 1e-8) {
      throw StateError(
        'Capital Guardian drawdown disagrees with durable account-equity truth.',
      );
    }
    return _snapshot(
      equity: equity,
      guardian: guardian,
      riskLimit: ledger.dailyRisk.limit,
      openRisk: ledger.dailyRisk.openRisk,
      remainingRisk: ledger.dailyRisk.available,
    );
  }

  LocalLiveCapitalGuardianSnapshot _snapshot({
    required _EquityTruth equity,
    required CapitalGuardianState guardian,
    required double riskLimit,
    required double openRisk,
    required double remainingRisk,
  }) => LocalLiveCapitalGuardianSnapshot(
    currentEquity: equity.currentEquity,
    peakEquity: equity.peakEquity,
    drawdownFraction: guardian.drawdownFraction,
    drawdownTier: guardian.drawdownTier,
    riskMultiplier: guardian.riskMultiplier(_policy),
    riskLimit: riskLimit,
    openRisk: openRisk,
    remainingRisk: remainingRisk,
    asOf: equity.asOf,
  );

  Future<_EquityTruth> _recordEquity({
    required double accountEquity,
    required DateTime now,
  }) async {
    final database = await _databaseFactory();
    if (database is! QuantaraAtomicDurableDatabase) {
      throw StateError(
        'Live capital high-water mark requires atomic durable storage.',
      );
    }
    final atomic = database as QuantaraAtomicDurableDatabase;
    return atomic.mutateRecord<_EquityTruth>(
      category: QuantaraDurableCategory.managedPositions,
      key: _localLiveCapitalEquityRecordKey,
      mutation: (current) async {
        final previous = current == null ? null : _EquityTruth.fromRecord(current);
        final peak = math.max(previous?.peakEquity ?? accountEquity, accountEquity);
        final drawdown = ((peak - accountEquity) / peak).clamp(0.0, 1.0);
        final next = _EquityTruth(
          currentEquity: accountEquity,
          peakEquity: peak,
          drawdownFraction: drawdown,
          asOf: now,
        );
        return QuantaraAtomicRecordMutation<_EquityTruth>(
          value: next,
          nextRecord: QuantaraDurableRecord(
            category: QuantaraDurableCategory.managedPositions,
            key: _localLiveCapitalEquityRecordKey,
            schemaVersion: 1,
            revision: (current?.revision ?? -1) + 1,
            updatedAt: now,
            payload: next.toJson(),
          ),
        );
      },
    );
  }
}

final class _EquityTruth {
  const _EquityTruth({
    required this.currentEquity,
    required this.peakEquity,
    required this.drawdownFraction,
    required this.asOf,
  });

  factory _EquityTruth.fromRecord(QuantaraDurableRecord record) {
    if (record.schemaVersion != 1) {
      throw const FormatException('Unsupported live capital equity schema.');
    }
    final current = (record.payload['currentEquity'] as num?)?.toDouble();
    final peak = (record.payload['peakEquity'] as num?)?.toDouble();
    final drawdown = (record.payload['drawdownFraction'] as num?)?.toDouble();
    final asOf = DateTime.tryParse(record.payload['asOf']?.toString() ?? '')?.toUtc();
    if (current == null ||
        peak == null ||
        drawdown == null ||
        asOf == null ||
        !current.isFinite ||
        !peak.isFinite ||
        !drawdown.isFinite ||
        current <= 0 ||
        peak <= 0 ||
        current > peak + 1e-8 ||
        drawdown < 0 ||
        drawdown > 1) {
      throw const FormatException('Persisted live capital equity is invalid.');
    }
    final expected = ((peak - current) / peak).clamp(0.0, 1.0);
    if ((expected - drawdown).abs() > 1e-8) {
      throw const FormatException(
        'Persisted live capital drawdown failed integrity validation.',
      );
    }
    return _EquityTruth(
      currentEquity: current,
      peakEquity: peak,
      drawdownFraction: drawdown,
      asOf: asOf,
    );
  }

  final double currentEquity;
  final double peakEquity;
  final double drawdownFraction;
  final DateTime asOf;

  Map<String, Object?> toJson() => {
    'currentEquity': currentEquity,
    'peakEquity': peakEquity,
    'drawdownFraction': drawdownFraction,
    'asOf': asOf.toUtc().toIso8601String(),
  };
}