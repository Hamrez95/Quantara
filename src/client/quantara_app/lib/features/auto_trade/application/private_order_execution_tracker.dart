import 'dart:collection';

import '../domain/private_truth_models.dart';

final class PrivateOrderExecutionObservation {
  const PrivateOrderExecutionObservation({
    required this.correlationId,
    required this.orderId,
    required this.clientId,
    required this.symbol,
    required this.orderStatus,
    this.submitAtUtc,
    required this.acknowledgedAtUtc,
    required this.firstFillAtUtc,
    required this.finalFillAtUtc,
    required this.filledQuantity,
    required this.orderQuantity,
    required this.weightedAverageFillPrice,
    required this.ambiguous,
  });

  final String correlationId;
  final String orderId;
  final String clientId;
  final String symbol;
  final String orderStatus;
  final DateTime? submitAtUtc;
  final DateTime acknowledgedAtUtc;
  final DateTime? firstFillAtUtc;
  final DateTime? finalFillAtUtc;
  final double filledQuantity;
  final double orderQuantity;
  final double? weightedAverageFillPrice;
  final bool ambiguous;

  double? get fillRatio {
    if (orderQuantity <= 0 || !orderQuantity.isFinite) return null;
    return (filledQuantity / orderQuantity).clamp(0.0, 1.0).toDouble();
  }
}

final class PrivateOrderExecutionTracker {
  PrivateOrderExecutionTracker({this.maximumEntries = 128}) {
    if (maximumEntries < 1) {
      throw const FormatException(
        'Private order execution tracker capacity must be positive.',
      );
    }
  }

  final int maximumEntries;
  final LinkedHashMap<String, PrivateOrderExecutionObservation> _byOrderId =
      LinkedHashMap<String, PrivateOrderExecutionObservation>();
  final LinkedHashMap<String, DateTime> _pendingSubmissions =
      LinkedHashMap<String, DateTime>();

  int get length => _byOrderId.length;

  PrivateOrderExecutionObservation? observationFor(String orderId) =>
      _byOrderId[orderId.trim()];

  void recordSubmission({
    required String correlationId,
    required DateTime submittedAtUtc,
  }) {
    final normalizedCorrelationId = correlationId.trim();
    if (normalizedCorrelationId.isEmpty || !submittedAtUtc.isUtc) {
      throw const FormatException('Order submission timing is invalid.');
    }
    _pendingSubmissions.remove(normalizedCorrelationId);
    _pendingSubmissions[normalizedCorrelationId] = submittedAtUtc;
    while (_pendingSubmissions.length > maximumEntries) {
      _pendingSubmissions.remove(_pendingSubmissions.keys.first);
    }
  }

  void clear() {
    _byOrderId.clear();
    _pendingSubmissions.clear();
  }

  void recordAccepted(PrivateTruthEvent event) {
    final payload = event.payload;
    if (payload is! PrivateOrderUpdate) return;

    final orderId = payload.orderId.trim();
    final symbol = payload.symbol.trim().toUpperCase();
    if (orderId.isEmpty || symbol.isEmpty) return;

    final observedAtUtc = event.exchangeTimestampUtc.toUtc();
    final previous = _byOrderId[orderId];
    final invalidFill = !payload.dealAmount.isFinite || payload.dealAmount < 0;
    final regressedFill =
        !invalidFill &&
        previous != null &&
        payload.dealAmount + 1e-9 < previous.filledQuantity;
    final filledQuantity = invalidFill || regressedFill
        ? previous?.filledQuantity ?? 0
        : payload.dealAmount;
    final weightedAverageFillPrice = invalidFill || regressedFill
        ? previous?.weightedAverageFillPrice
        : payload.averagePrice > 0 && payload.averagePrice.isFinite
        ? payload.averagePrice
        : previous?.weightedAverageFillPrice;
    final firstFillAtUtc =
        previous?.firstFillAtUtc ?? (filledQuantity > 0 ? observedAtUtc : null);
    final isFilled = payload.orderStatus.trim().toUpperCase() == 'FILLED';
    final correlationId =
        previous?.correlationId ??
        (payload.clientId.trim().isNotEmpty
            ? payload.clientId.trim()
            : orderId);
    final submitAtUtc =
        previous?.submitAtUtc ?? _pendingSubmissions.remove(correlationId);
    final clientId = payload.clientId.trim().isNotEmpty
        ? payload.clientId.trim()
        : previous?.clientId ?? '';
    final orderQuantity = payload.quantity > 0 && payload.quantity.isFinite
        ? payload.quantity
        : previous?.orderQuantity ?? 0;
    final overfilled =
        orderQuantity > 0 && filledQuantity > orderQuantity + 1e-9;
    final acknowledgementBeforeSubmit =
        submitAtUtc != null && observedAtUtc.isBefore(submitAtUtc);
    final finalFillAtUtc =
        previous?.finalFillAtUtc ??
        (isFilled &&
                !invalidFill &&
                !regressedFill &&
                !overfilled &&
                filledQuantity > 0
            ? observedAtUtc
            : null);

    _byOrderId[orderId] = PrivateOrderExecutionObservation(
      correlationId: correlationId,
      orderId: orderId,
      clientId: clientId,
      symbol: symbol,
      orderStatus: payload.orderStatus.trim().toUpperCase(),
      submitAtUtc: submitAtUtc,
      acknowledgedAtUtc: previous?.acknowledgedAtUtc ?? observedAtUtc,
      firstFillAtUtc: firstFillAtUtc,
      finalFillAtUtc: finalFillAtUtc,
      filledQuantity: filledQuantity,
      orderQuantity: orderQuantity,
      weightedAverageFillPrice: weightedAverageFillPrice,
      ambiguous:
          (previous?.ambiguous ?? false) ||
          invalidFill ||
          regressedFill ||
          overfilled ||
          acknowledgementBeforeSubmit,
    );

    while (_byOrderId.length > maximumEntries) {
      _byOrderId.remove(_byOrderId.keys.first);
    }
  }
}
