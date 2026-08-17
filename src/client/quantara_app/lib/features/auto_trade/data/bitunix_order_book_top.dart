import '../domain/execution_quality_models.dart';

final class BitunixOrderBookTop {
  const BitunixOrderBookTop({required this.bestBid, required this.bestAsk});

  factory BitunixOrderBookTop.fromApiPayload(Object? payload) {
    if (payload is! Map<Object?, Object?>) {
      throw const FormatException('Bitunix order book payload is invalid.');
    }
    final data = payload['data'];
    if (data is! Map<Object?, Object?>) {
      throw const FormatException('Bitunix order book data is invalid.');
    }
    final bestBid = _firstLevelPrice(data['bids'], side: 'bid');
    final bestAsk = _firstLevelPrice(data['asks'], side: 'ask');
    if (bestBid >= bestAsk) {
      throw const FormatException('Bitunix order book is crossed or locked.');
    }
    return BitunixOrderBookTop(bestBid: bestBid, bestAsk: bestAsk);
  }

  final double bestBid;
  final double bestAsk;

  double executablePriceFor(ExecutionSide side) => switch (side) {
    ExecutionSide.long => bestAsk,
    ExecutionSide.short => bestBid,
  };
}

double _firstLevelPrice(Object? value, {required String side}) {
  if (value is! List<Object?> || value.isEmpty) {
    throw FormatException('Bitunix order book $side side is empty.');
  }
  final level = value.first;
  if (level is! List<Object?> || level.length < 2) {
    throw FormatException('Bitunix order book $side level is invalid.');
  }
  final raw = level.first;
  final price = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
  if (price == null || !price.isFinite || price <= 0) {
    throw FormatException('Bitunix order book $side price is invalid.');
  }
  return price;
}
