final class TradingLabAccountContext {
  const TradingLabAccountContext({
    required this.connected,
    required this.reconciliationHealth,
    required this.refreshing,
    required this.blocksNewEntries,
    required this.canManageExistingPositions,
    this.syncedAtUtc,
    this.marginCoin,
    this.available,
    this.frozen,
    this.positionMargin,
    this.unrealizedPnl,
    this.estimatedEquity,
    this.openPositionCount,
    this.pendingOrderCount,
    this.allOpenPositionsFullyProtected,
    this.warning,
  });

  factory TradingLabAccountContext.disconnected() =>
      const TradingLabAccountContext(
        connected: false,
        reconciliationHealth: 'unavailable',
        refreshing: false,
        blocksNewEntries: true,
        canManageExistingPositions: false,
      );

  final bool connected;
  final String reconciliationHealth;
  final bool refreshing;
  final bool blocksNewEntries;
  final bool canManageExistingPositions;
  final DateTime? syncedAtUtc;
  final String? marginCoin;
  final double? available;
  final double? frozen;
  final double? positionMargin;
  final double? unrealizedPnl;
  final double? estimatedEquity;
  final int? openPositionCount;
  final int? pendingOrderCount;
  final bool? allOpenPositionsFullyProtected;
  final String? warning;

  Map<String, Object?> toJson() => {
    'connected': connected,
    'reconciliationHealth': reconciliationHealth,
    'refreshing': refreshing,
    'blocksNewEntries': blocksNewEntries,
    'canManageExistingPositions': canManageExistingPositions,
    'syncedAtUtc': syncedAtUtc?.toUtc().toIso8601String(),
    'marginCoin': marginCoin,
    'available': available,
    'frozen': frozen,
    'positionMargin': positionMargin,
    'unrealizedPnl': unrealizedPnl,
    'estimatedEquity': estimatedEquity,
    'openPositionCount': openPositionCount,
    'pendingOrderCount': pendingOrderCount,
    'allOpenPositionsFullyProtected': allOpenPositionsFullyProtected,
    'warning': warning,
    'authority': 'read_only_context',
  };
}
