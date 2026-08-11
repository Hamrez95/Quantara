final class TradingLabRealAccountTradeEvidence {
  TradingLabRealAccountTradeEvidence({
    required this.symbol,
    required this.side,
    required this.state,
    required this.quantity,
    required this.averageEntryPrice,
    required this.averageExitPrice,
    required this.realizedGrossPnl,
    required this.fees,
    required this.funding,
    required this.netRealizedPnl,
    required this.unrealizedPnl,
    required this.openedAtUtc,
    required this.closedAtUtc,
    required this.asOfUtc,
    required this.verified,
  }) {
    if (symbol.trim().isEmpty || !asOfUtc.isUtc) {
      throw const FormatException(
        'Invalid sanitized real-account trade evidence.',
      );
    }
    if (openedAtUtc != null && !openedAtUtc!.isUtc ||
        closedAtUtc != null && !closedAtUtc!.isUtc ||
        openedAtUtc != null &&
            closedAtUtc != null &&
            closedAtUtc!.isBefore(openedAtUtc!)) {
      throw const FormatException(
        'Invalid sanitized real-account trade chronology.',
      );
    }
  }

  final String symbol;
  final String side;
  final String state;
  final double quantity;
  final double? averageEntryPrice;
  final double? averageExitPrice;
  final double? realizedGrossPnl;
  final double? fees;
  final double? funding;
  final double? netRealizedPnl;
  final double? unrealizedPnl;
  final DateTime? openedAtUtc;
  final DateTime? closedAtUtc;
  final DateTime asOfUtc;
  final bool verified;

  Map<String, Object?> toJson() => {
    'symbol': symbol,
    'side': side,
    'state': state,
    'quantity': quantity,
    'averageEntryPrice': averageEntryPrice,
    'averageExitPrice': averageExitPrice,
    'realizedGrossPnl': realizedGrossPnl,
    'fees': fees,
    'funding': funding,
    'netRealizedPnl': netRealizedPnl,
    'unrealizedPnl': unrealizedPnl,
    'openedAtUtc': openedAtUtc?.toIso8601String(),
    'closedAtUtc': closedAtUtc?.toIso8601String(),
    'asOfUtc': asOfUtc.toIso8601String(),
    'verified': verified,
  };
}

final class TradingLabRealAccountEvidence {
  TradingLabRealAccountEvidence({
    required this.currency,
    required this.asOfUtc,
    required this.verified,
    required this.fillsAvailable,
    required this.settlementsAvailable,
    required this.accountUnrealizedPnl,
    required this.accountRealizedGrossPnl,
    required this.accountFees,
    required this.accountFunding,
    required this.accountNetRealizedPnl,
    required this.sourceWarningPresent,
    Iterable<TradingLabRealAccountTradeEvidence> trades = const [],
  }) : trades = List.unmodifiable(trades) {
    if (currency.trim().isEmpty || !asOfUtc.isUtc) {
      throw const FormatException('Invalid sanitized real-account evidence.');
    }
  }

  factory TradingLabRealAccountEvidence.unavailable({DateTime? asOfUtc}) =>
      TradingLabRealAccountEvidence(
        currency: 'USDT',
        asOfUtc: (asOfUtc ?? DateTime.now()).toUtc(),
        verified: false,
        fillsAvailable: false,
        settlementsAvailable: false,
        accountUnrealizedPnl: null,
        accountRealizedGrossPnl: null,
        accountFees: null,
        accountFunding: null,
        accountNetRealizedPnl: null,
        sourceWarningPresent: false,
      );

  final String currency;
  final DateTime asOfUtc;
  final bool verified;
  final bool fillsAvailable;
  final bool settlementsAvailable;
  final double? accountUnrealizedPnl;
  final double? accountRealizedGrossPnl;
  final double? accountFees;
  final double? accountFunding;
  final double? accountNetRealizedPnl;
  final bool sourceWarningPresent;
  final List<TradingLabRealAccountTradeEvidence> trades;

  Map<String, Object?> toJson() => {
    'schema': 'quantara.trading_lab.real_account_evidence.v1',
    'sanitized': true,
    'containsExchangeIdentifiers': false,
    'currency': currency,
    'asOfUtc': asOfUtc.toIso8601String(),
    'verified': verified,
    'fillsAvailable': fillsAvailable,
    'settlementsAvailable': settlementsAvailable,
    'accountUnrealizedPnl': accountUnrealizedPnl,
    'accountRealizedGrossPnl': accountRealizedGrossPnl,
    'accountFees': accountFees,
    'accountFunding': accountFunding,
    'accountNetRealizedPnl': accountNetRealizedPnl,
    'sourceWarningPresent': sourceWarningPresent,
    'tradeCount': trades.length,
  };
}
