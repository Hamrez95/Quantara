import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/profit_lock_stop_policy.dart';

final class ProfitLockPromotionExecution {
  const ProfitLockPromotionExecution({
    required this.confirmed,
    required this.requestSubmitted,
    this.orderId,
    this.confirmedStop,
    this.warning,
  });

  final bool confirmed;
  final bool requestSubmitted;
  final String? orderId;
  final double? confirmedStop;
  final String? warning;
}

final class ProfitLockPromotionExecutor {
  ProfitLockPromotionExecutor({
    this.confirmationAttempts = 4,
    this.confirmationDelay = const Duration(milliseconds: 450),
    Future<void> Function(Duration duration)? delay,
  }) : delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final int confirmationAttempts;
  final Duration confirmationDelay;
  final Future<void> Function(Duration duration) delay;

  Future<ProfitLockPromotionExecution> execute({
    required TradeDirection direction,
    required ProfitLockStopDecision decision,
    required double priceTolerance,
    required Future<String> Function(double proposedStop) requestMutation,
    required Future<double?> Function() readConfirmedStop,
  }) async {
    if (!decision.requiresMutation) {
      return ProfitLockPromotionExecution(
        confirmed: true,
        requestSubmitted: false,
        confirmedStop: decision.proposedStop,
      );
    }

    String? orderId;
    Object? requestError;
    try {
      orderId = await requestMutation(decision.proposedStop);
    } on Object catch (error) {
      requestError = error;
    }

    for (var attempt = 0; attempt < confirmationAttempts; attempt++) {
      if (attempt > 0 || requestError == null) await delay(confirmationDelay);
      try {
        final confirmedStop = await readConfirmedStop();
        if (confirmedStop != null &&
            ProfitLockStopPolicy.isAtLeastAsSafe(
              direction: direction,
              confirmedStop: confirmedStop,
              proposedStop: decision.proposedStop,
              tolerance: priceTolerance,
            )) {
          return ProfitLockPromotionExecution(
            confirmed: true,
            requestSubmitted: true,
            orderId: orderId,
            confirmedStop: confirmedStop,
          );
        }
      } on Object {
        // Keep the previous exchange-confirmed stop authoritative and continue
        // only bounded read-after-write verification. Never resend mutation.
      }
    }

    return ProfitLockPromotionExecution(
      confirmed: false,
      requestSubmitted: true,
      orderId: orderId,
      warning: requestError == null
          ? 'Stop promotion was not confirmed by exchange protection truth.'
          : 'Stop promotion response was ambiguous and remained unconfirmed.',
    );
  }
}
