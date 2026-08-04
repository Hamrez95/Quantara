import '../../portfolio_risk/application/portfolio_risk_coordinator.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/local_live_portfolio_admission.dart';
import '../domain/local_live_trade_models.dart';
import '../domain/trading_pnl_projection.dart';
import 'local_live_portfolio_risk_runtime.dart';

final class LocalLivePortfolioExecutionGuard {
  LocalLivePortfolioExecutionGuard({required double dailyRiskLimit})
    : _runtime = LocalLivePortfolioRiskRuntime(
        dailyRiskLimit: dailyRiskLimit,
      );

  final LocalLivePortfolioRiskRuntime _runtime;

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
    final truth = LocalLivePortfolioAdmission.accountTruth(
      account: account,
      observedAt: now,
      allOpenPositionsProtected: allOpenPositionsProtected,
    );
    return _runtime.reserve(candidate: candidate, account: truth, now: now);
  }

  Future<void> releaseBeforeOrder({
    required String reservationId,
    required String setupId,
    required DateTime now,
  }) async {
    await _runtime.release(
      reservationId: reservationId,
      eventId: 'release-before-order:$setupId',
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

  Future<PortfolioRiskSnapshot> snapshot({
    required AutoTradeAccountSnapshot account,
    required bool allOpenPositionsProtected,
    required DateTime now,
  }) => _runtime.snapshot(
    account: LocalLivePortfolioAdmission.accountTruth(
      account: account,
      observedAt: now,
      allOpenPositionsProtected: allOpenPositionsProtected,
    ),
    now: now,
  );
}
