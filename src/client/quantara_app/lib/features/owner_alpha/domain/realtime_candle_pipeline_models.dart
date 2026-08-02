import '../../market_analysis/domain/market_chart_models.dart';
import 'bitunix_public_stream_models.dart';

final class RealtimeCandleStreamKey {
  RealtimeCandleStreamKey({required String symbol, required this.interval})
    : symbol = _normalizeSymbol(symbol);

  final String symbol;
  final BitunixKlineInterval interval;

  String get timeframe => interval.timeframe;

  String get id => '$symbol|${interval.timeframe}';

  static String _normalizeSymbol(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'symbol', 'Invalid futures symbol.');
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeCandleStreamKey &&
          symbol == other.symbol &&
          interval == other.interval;

  @override
  int get hashCode => Object.hash(symbol, interval);

  @override
  String toString() => id;
}

enum RealtimeCandlePipelineDisposition {
  bootstrapped,
  workingUpdated,
  candleClosed,
  duplicate,
  outOfOrder,
  gapDetected,
  blockedByGap,
  reconciled,
}

final class RealtimeCandleGap {
  RealtimeCandleGap({
    required this.fromOpenTimeUtc,
    required this.toOpenTimeExclusiveUtc,
    required this.observedWorkingOpenTimeUtc,
  }) {
    if (!fromOpenTimeUtc.isUtc ||
        !toOpenTimeExclusiveUtc.isUtc ||
        !observedWorkingOpenTimeUtc.isUtc) {
      throw ArgumentError('Gap timestamps must be UTC.');
    }
    if (!toOpenTimeExclusiveUtc.isAfter(fromOpenTimeUtc) ||
        observedWorkingOpenTimeUtc != toOpenTimeExclusiveUtc) {
      throw ArgumentError('Gap boundaries are invalid.');
    }
  }

  final DateTime fromOpenTimeUtc;
  final DateTime toOpenTimeExclusiveUtc;
  final DateTime observedWorkingOpenTimeUtc;

  Duration get missingDuration =>
      toOpenTimeExclusiveUtc.difference(fromOpenTimeUtc);
}

final class RealtimeCandlePipelineUpdate {
  RealtimeCandlePipelineUpdate({
    required this.key,
    required this.disposition,
    required this.workingCandle,
    required List<ChartCandle> closedCandles,
    required this.gap,
    required this.exchangeTimestampUtc,
    required this.receivedAtUtc,
    required this.processedAtUtc,
  }) : closedCandles = List.unmodifiable(closedCandles) {
    if (!exchangeTimestampUtc.isUtc ||
        !receivedAtUtc.isUtc ||
        !processedAtUtc.isUtc) {
      throw ArgumentError('All pipeline timestamps must be UTC.');
    }
    if (workingCandle != null && !workingCandle!.isValid) {
      throw ArgumentError('The working candle must be valid.');
    }
    if (this.closedCandles.any((candle) => !candle.isValid)) {
      throw ArgumentError('Closed candles must be valid.');
    }
  }

  final RealtimeCandleStreamKey key;
  final RealtimeCandlePipelineDisposition disposition;
  final ChartCandle? workingCandle;
  final List<ChartCandle> closedCandles;
  final RealtimeCandleGap? gap;
  final DateTime exchangeTimestampUtc;
  final DateTime receivedAtUtc;
  final DateTime processedAtUtc;

  bool get streamTrusted =>
      disposition != RealtimeCandlePipelineDisposition.gapDetected &&
      disposition != RealtimeCandlePipelineDisposition.blockedByGap;

  bool get allowsCandidatePreparation =>
      workingCandle != null &&
      (disposition == RealtimeCandlePipelineDisposition.workingUpdated ||
          disposition == RealtimeCandlePipelineDisposition.duplicate ||
          disposition == RealtimeCandlePipelineDisposition.candleClosed ||
          disposition == RealtimeCandlePipelineDisposition.reconciled);

  bool get triggersClosedCandleAnalysis =>
      disposition == RealtimeCandlePipelineDisposition.candleClosed ||
      disposition == RealtimeCandlePipelineDisposition.reconciled;

  bool get isCritical =>
      disposition == RealtimeCandlePipelineDisposition.bootstrapped ||
      triggersClosedCandleAnalysis ||
      disposition == RealtimeCandlePipelineDisposition.gapDetected ||
      disposition == RealtimeCandlePipelineDisposition.blockedByGap ||
      disposition == RealtimeCandlePipelineDisposition.outOfOrder;
}

final class RealtimeCandleStreamSnapshot {
  RealtimeCandleStreamSnapshot({
    required this.key,
    required List<ChartCandle> closedCandles,
    required this.workingCandle,
    required this.gap,
  }) : closedCandles = List.unmodifiable(closedCandles);

  final RealtimeCandleStreamKey key;
  final List<ChartCandle> closedCandles;
  final ChartCandle? workingCandle;
  final RealtimeCandleGap? gap;

  bool get trusted => gap == null;
}
