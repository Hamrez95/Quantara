enum AutoTradeConnectionState {
  disconnected,
  connecting,
  readOnly,
  error,
}

final class BitunixApiCredentials {
  const BitunixApiCredentials({
    required this.apiKey,
    required this.secretKey,
  });

  final String apiKey;
  final String secretKey;

  String get maskedApiKey {
    if (apiKey.length <= 8) return '••••••••';
    return '${apiKey.substring(0, 4)}••••${apiKey.substring(apiKey.length - 4)}';
  }
}

final class AutoTradeAccountSnapshot {
  const AutoTradeAccountSnapshot({
    required this.marginCoin,
    required this.available,
    required this.frozen,
    required this.positionMargin,
    required this.crossUnrealizedPnl,
    required this.isolatedUnrealizedPnl,
    required this.positionMode,
    required this.positions,
    required this.orders,
    required this.syncedAt,
  });

  final String marginCoin;
  final double available;
  final double frozen;
  final double positionMargin;
  final double crossUnrealizedPnl;
  final double isolatedUnrealizedPnl;
  final String positionMode;
  final List<AutoTradePosition> positions;
  final List<AutoTradeOrder> orders;
  final DateTime syncedAt;

  double get totalUnrealizedPnl =>
      crossUnrealizedPnl + isolatedUnrealizedPnl;

  double get estimatedEquity =>
      available + frozen + positionMargin + totalUnrealizedPnl;
}

final class AutoTradePosition {
  const AutoTradePosition({
    required this.positionId,
    required this.symbol,
    required this.quantity,
    required this.side,
    required this.marginMode,
    required this.positionMode,
    required this.leverage,
    required this.margin,
    required this.unrealizedPnl,
    required this.liquidationPrice,
    required this.averageOpenPrice,
  });

  final String positionId;
  final String symbol;
  final double quantity;
  final String side;
  final String marginMode;
  final String positionMode;
  final int leverage;
  final double margin;
  final double unrealizedPnl;
  final double liquidationPrice;
  final double averageOpenPrice;
}

final class AutoTradeOrder {
  const AutoTradeOrder({
    required this.orderId,
    required this.clientId,
    required this.symbol,
    required this.quantity,
    required this.filledQuantity,
    required this.side,
    required this.orderType,
    required this.marginMode,
    required this.leverage,
    required this.reduceOnly,
  });

  final String orderId;
  final String clientId;
  final String symbol;
  final double quantity;
  final double filledQuantity;
  final String side;
  final String orderType;
  final String marginMode;
  final int leverage;
  final bool reduceOnly;
}

final class AutoTradeSafeException implements Exception {
  const AutoTradeSafeException(this.message, {this.code});

  final String message;
  final Object? code;

  @override
  String toString() => message;
}
