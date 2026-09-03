import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../portfolio_risk/application/portfolio_risk_coordinator.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/local_live_portfolio_admission.dart';
import '../domain/local_live_trade_models.dart';
import '../domain/trading_pnl_projection.dart';
import 'local_live_account_truth_coherence.dart';
import 'local_live_admission_telemetry.dart';
import 'local_live_capital_guardian_monitor.dart';
import 'local_live_portfolio_risk_runtime.dart';

final class LocalLivePortfolioExecutionGuard {
  LocalLivePortfolioExecutionGuard({
    required double dailyRiskLimit,
    LocalLiveCapitalGuardianMonitor? capitalGuardianMonitor,
    LocalLiveAdmissionTelemetryCollector? admissionTelemetry,
  }) : _runtime = LocalLivePortfolioRiskRuntime(dailyRiskLimit: dailyRiskLimit),
       _capitalGuardianMonitor =
           capitalGuardianMonitor ?? LocalLiveCapitalGuardianMonitor(),
       _admissionTelemetry =
           admissionTelemetry ?? LocalLiveAdmissionTelemetryCollector();

  final LocalLivePortfolioRiskRuntime _runtime;
  final LocalLiveCapitalGuardianMonitor _capitalGuardianMonitor;
  final LocalLiveAdmissionTelemetryCollector _admissionTelemetry;

  List<LocalLiveAdmissionFreshnessEvent> get admissionFreshnessTelemetry =>
      _admissionTelemetry.events;

  Future<PortfolioReservationOutcome> preview({
    required TradeIdea idea,
    required double plannedQuantity,
    required double entryPrice,
    required double stopPrice,
    required double requiredMargin,
    required int leverage,
    required double minimumQuantity,
    required double minimumNotional,
    required AutoTradeAccountSnapshot account,
    required bool allOpenPositionsProtected,
    required DateTime now,
  }) {
    final candidate = LocalLivePortfolioAdmission.candidate(
      idea: idea,
      plannedQuantity: plannedQuantity,
      entryPrice: entryPrice,
      stopPrice: stopPrice,
      requiredMargin: requiredMargin,
      leverage: leverage,
      minimumQuantity: minimumQuantity,
      minimumNotional: minimumNotional,
    );
    final resolved = _resolveAccount(account: account, now: now);
    final truth = LocalLivePortfolioAdmission.accountTruth(
      account: resolved.account,
      observedAt: now,
      allOpenPositionsProtected:
          allOpenPositionsProtected &&
          resolved.account.allOpenPositionsFullyProtected,
    );
    return _runtime.preview(candidate: candidate, account: truth, now: now);
  }

  Future<PortfolioReservationOutcome> reserve({
    required TradeIdea idea,
    required double plannedQuantity,
    required double entryPrice,
    required double stopPrice,
    required double requiredMargin,
    required int leverage,
    required double minimumQuantity,
    required double minimumNotional,
    required AutoTradeAccountSnapshot account,
    required bool allOpenPositionsProtected,
    required DateTime now,
  }) async {
    final candidate = LocalLivePortfolioAdmission.candidate(
      idea: idea,
      plannedQuantity: plannedQuantity,
      entryPrice: entryPrice,
      stopPrice: stopPrice,
      requiredMargin: requiredMargin,
      leverage: leverage,
      minimumQuantity: minimumQuantity,
      minimumNotional: minimumNotional,
    );
    final resolved = _resolveAccount(account: account, now: now);
    final truth = LocalLivePortfolioAdmission.accountTruth(
      account: resolved.account,
      observedAt: now,
      allOpenPositionsProtected:
          allOpenPositionsProtected &&
          resolved.account.allOpenPositionsFullyProtected,
    );
    final outcome = await _runtime.reserve(
      candidate: candidate,
      account: truth,
      now: now,
    );
    final staleRejected =
        outcome.decision.reason == PortfolioEntryBlockReason.staleAccount;
    if (resolved.refreshAttempted || staleRejected) {
      final fallbackAsOf = account.syncedAt.toUtc();
      final observedAt = now.toUtc();
      final fallbackAge = observedAt.difference(fallbackAsOf);
      await _admissionTelemetry.recordFreshnessDecision(
        eventType: resolved.recoveredFromStaleFallback
            ? 'stale_account_recovered'
            : 'stale_account_rejected',
        timestampUtc: observedAt,
        idea: idea,
        accountSnapshotAsOfUtc: fallbackAsOf,
        reconciliationCompletedAtUtc:
            resolved.reconciliationCompletedAtUtc,
        budgetGeneration: resolved.reconciliationGeneration,
        budgetAsOfUtc: resolved.account.syncedAt,
        age: fallbackAge,
        threshold: LocalLivePortfolioAdmission.accountFreshnessWindow,
        staleReasonCode: resolved.recoveredFromStaleFallback
            ? 'scan_snapshot_stale_reconciled_truth_fresh'
            : 'account_truth_outside_freshness_window',
        refreshAttempt: resolved.refreshAttempted,
        refreshResult: resolved.refreshResult,
        finalAdmissionDecision:
            outcome.decision.allowed && outcome.decision.liveExecutionAllowed
            ? 'allowed'
            : 'blocked:${outcome.decision.reason.name}',
      );
    }
    return outcome;
  }

  LocalLiveAccountTruthResolution _resolveAccount({
    required AutoTradeAccountSnapshot account,
    required DateTime now,
  }) => LocalLiveAccountTruthCoherence.resolve(
    fallback: account,
    observedAtUtc: now,
    freshnessWindow: LocalLivePortfolioAdmission.accountFreshnessWindow,
  );

  Future<PortfolioRiskLedger> adoptVerifiedOpenPosition({
    required LocalLiveManagedPosition managed,
    required double confirmedStop,
    required DateTime now,
  }) => _runtime.adoptVerifiedOpenPosition(
    managed: managed,
    confirmedStop: confirmedStop,
    now: now,
  );

  Future<void> releaseNoExposure({
    required String reservationId,
    required String evidence,
    required DateTime now,
  }) async {
    await _runtime.release(
      reservationId: reservationId,
      eventId: 'release:$reservationId:$evidence',
      now: now,
    );
  }

  Future<void> markAmbiguous({
    required String reservationId,
    required String evidence,
    required DateTime now,
  }) async {
    await _runtime.markAmbiguous(
      reservationId: reservationId,
      eventId: 'ambiguous:$reservationId:$evidence',
      now: now,
    );
  }

  Future<void> recordFill({
    required String reservationId,
    required String orderId,
    required String positionId,
    required double fillQuantity,
    required DateTime now,
  }) async {
    await _runtime.recordFill(
      reservationId: reservationId,
      eventId: 'fill:$orderId:${fillQuantity.toStringAsFixed(12)}',
      entryOrderId: orderId,
      positionId: positionId,
      fillQuantity: fillQuantity,
      now: now,
    );
  }

  Future<void> confirmStop({
    required String positionId,
    required double confirmedStop,
    required DateTime now,
  }) async {
    await _runtime.confirmStop(
      positionId: positionId,
      eventId: 'stop:$positionId:${confirmedStop.toStringAsFixed(12)}',
      confirmedStop: confirmedStop,
      now: now,
    );
  }

  Future<void> confirmReduction({
    required String positionId,
    required double remainingQuantity,
    required Set<String> exchangeFillIds,
    required DateTime now,
  }) async {
    final evidence = exchangeFillIds.toList(growable: false)..sort();
    await _runtime.reduce(
      positionId: positionId,
      eventId:
          'reduce:$positionId:${remainingQuantity.toStringAsFixed(12)}:${evidence.join(',')}',
      remainingQuantity: remainingQuantity,
      now: now,
    );
  }

  Future<PortfolioRiskLedger> reconcileRestartAndClosedPositions({
    required List<LocalLiveManagedPosition> managed,
    required List<BitunixLivePosition> exchangePositions,
    required TradingPnlProjection pnlProjection,
    required DateTime now,
  }) async {
    var ledger = await _runtime.load(now: now);
    final managedIds = managed
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final exchangeIds = exchangePositions
        .where((item) => item.quantity > 0)
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();

    for (final reservation in ledger.activeReservations) {
      final positionId = reservation.positionId?.trim() ?? '';
      if (positionId.isEmpty) {
        if (!reservation.ambiguous) {
          ledger = await _runtime.markAmbiguous(
            reservationId: reservation.reservationId,
            eventId: 'restart-pending:${reservation.reservationId}',
            now: now,
          );
        }
        continue;
      }
      if (exchangeIds.contains(positionId)) continue;
      final projection = pnlProjection.forPositionId(positionId);
      final net = projection?.netRealized;
      if (projection != null &&
          projection.isVerified &&
          net != null &&
          net.isFinal &&
          net.value != null) {
        ledger = await _runtime.close(
          positionId: positionId,
          eventId:
              'close:$positionId:${net.asOf.toUtc().microsecondsSinceEpoch}',
          exchangeConfirmedNetPnl: net.value!,
          now: now,
        );
      } else if (!reservation.ambiguous) {
        ledger = await _runtime.markAmbiguous(
          reservationId: reservation.reservationId,
          eventId: 'closed-pnl-pending:$positionId',
          now: now,
        );
      }
    }

    final ledgerPositionIds = ledger.activeReservations
        .map((item) => item.positionId?.trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet();
    final legacyManaged = managedIds.difference(ledgerPositionIds);
    if (legacyManaged.isNotEmpty) {
      throw const LocalLiveTradeSafeException(
        'Existing managed exposure predates the atomic portfolio ledger. New entries remain blocked until it closes and exchange PnL is reconciled.',
      );
    }
    return ledger;
  }

  Future<LocalLivePortfolioGuardSnapshot> snapshot({
    required AutoTradeAccountSnapshot account,
    required bool allOpenPositionsProtected,
    required DateTime now,
  }) async {
    final resolved = _resolveAccount(account: account, now: now);
    final riskSnapshot = await _runtime.snapshot(
      account: LocalLivePortfolioAdmission.accountTruth(
        account: resolved.account,
        observedAt: now,
        allOpenPositionsProtected:
            allOpenPositionsProtected &&
            resolved.account.allOpenPositionsFullyProtected,
      ),
      now: now,
    );
    final guardian = await _capitalGuardianMonitor.refresh(
      accountEquity: resolved.account.estimatedEquity,
      now: now,
    );
    return LocalLivePortfolioGuardSnapshot(
      risk: riskSnapshot,
      guardian: guardian,
    );
  }
}

/// One coherent projection from the existing atomic risk/Guardian refresh.
///
/// Keeping the values together prevents the UI from triggering a second durable
/// read merely to display the Capital Guardian state.
final class LocalLivePortfolioGuardSnapshot {
  const LocalLivePortfolioGuardSnapshot({
    required this.risk,
    required this.guardian,
  });

  final PortfolioRiskSnapshot risk;
  final LocalLiveCapitalGuardianSnapshot guardian;
}
