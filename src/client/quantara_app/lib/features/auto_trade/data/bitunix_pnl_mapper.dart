import '../domain/trading_pnl_projection.dart';

final class BitunixPnlParseResult<T> {
  const BitunixPnlParseResult({
    required this.values,
    required this.verified,
    this.warning,
  });

  final List<T> values;
  final bool verified;
  final String? warning;
}

final class BitunixPnlMapper {
  const BitunixPnlMapper._();

  static BitunixPnlParseResult<ExchangePositionSettlement> settlements(
    Object? data,
  ) {
    final rows = _nestedList(data, 'positionList');
    final values = <ExchangePositionSettlement>[];
    final warnings = <String>[];
    for (final row in rows) {
      final positionId = _string(row['positionId']);
      final symbol = _string(row['symbol']).toUpperCase();
      final closedAt = _timestamp(row['mtime']);
      if (positionId.isEmpty || symbol.isEmpty || closedAt == null) {
        warnings.add('Malformed Bitunix position-history row.');
        continue;
      }
      values.add(
        ExchangePositionSettlement(
          positionId: positionId,
          symbol: symbol,
          funding: _optionalNumber(row['funding']),
          openedAt: _timestamp(row['ctime']),
          closedAt: closedAt,
          realizedPnl: _optionalNumber(row['realizedPNL']),
          fee: _optionalNumber(row['fee']),
        ),
      );
    }
    return BitunixPnlParseResult(
      values: List.unmodifiable(values),
      verified: warnings.isEmpty,
      warning: warnings.isEmpty ? null : warnings.toSet().join(' '),
    );
  }

  static BitunixPnlParseResult<ExchangePnlFill> fills(
    Object? data, {
    required Iterable<ExchangeUnrealizedPnl> openPositions,
    required Iterable<ExchangePositionSettlement> settlements,
  }) {
    final rows = _nestedList(data, 'tradeList');
    final open = openPositions.toList(growable: false);
    final closed = settlements.toList(growable: false);
    final values = <ExchangePnlFill>[];
    final warnings = <String>[];
    for (final row in rows) {
      final tradeId = _string(row['tradeId']);
      final orderId = _string(row['orderId']);
      final symbol = _string(row['symbol']).toUpperCase();
      final quantity = _optionalNumber(row['qty']);
      final price = _optionalNumber(row['price']);
      final realized = _optionalNumber(row['realizedPNL']);
      final fee = _optionalNumber(row['fee']);
      final occurredAt = _timestamp(row['ctime']);
      if (tradeId.isEmpty ||
          orderId.isEmpty ||
          symbol.isEmpty ||
          quantity == null ||
          price == null ||
          realized == null ||
          fee == null ||
          occurredAt == null) {
        warnings.add('Malformed Bitunix trade-history row.');
        continue;
      }
      final directPositionId = _string(row['positionId']);
      final resolved = directPositionId.isNotEmpty
          ? directPositionId
          : _resolvePositionId(
              symbol: symbol,
              occurredAt: occurredAt,
              openPositions: open,
              settlements: closed,
            );
      if (resolved == null) {
        warnings.add(
          'Trade $tradeId could not be assigned to one exchange position.',
        );
      }
      values.add(
        ExchangePnlFill(
          tradeId: tradeId,
          orderId: orderId,
          positionId: resolved ?? '',
          symbol: symbol,
          quantity: quantity.abs(),
          price: price,
          realizedPnl: realized,
          fee: fee.abs(),
          reduceOnly: row['reduceOnly'] == true,
          occurredAt: occurredAt,
          clientId: _string(row['clientId']),
          side: _string(row['side']).toUpperCase(),
        ),
      );
    }
    return BitunixPnlParseResult(
      values: List.unmodifiable(values),
      verified: warnings.isEmpty,
      warning: warnings.isEmpty ? null : warnings.toSet().join(' '),
    );
  }

  static String? _resolvePositionId({
    required String symbol,
    required DateTime occurredAt,
    required List<ExchangeUnrealizedPnl> openPositions,
    required List<ExchangePositionSettlement> settlements,
  }) {
    final at = occurredAt.toUtc();
    final closedMatches = settlements
        .where((item) {
          if (item.symbol.toUpperCase() != symbol) return false;
          final openedAt = item.openedAt;
          if (openedAt != null && at.isBefore(openedAt.toUtc())) return false;
          return !at.isAfter(item.closedAt.toUtc());
        })
        .map((item) => item.positionId)
        .where((item) => item.isNotEmpty)
        .toSet();
    if (closedMatches.length == 1) return closedMatches.single;
    if (closedMatches.length > 1) return null;

    final openMatches = openPositions
        .where((item) => item.symbol.toUpperCase() == symbol)
        .map((item) => item.positionId)
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    if (openMatches.length == 1) return openMatches.single;
    return null;
  }

  static List<Map<String, Object?>> _nestedList(Object? data, String key) {
    if (data is Map<String, Object?>) return _mapList(data[key]);
    if (data is Map<Object?, Object?>) return _mapList(data[key]);
    return _mapList(data);
  }

  static List<Map<String, Object?>> _mapList(Object? value) {
    if (value is! List<Object?>) return const [];
    return value
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) =>
              item.map((key, itemValue) => MapEntry(key.toString(), itemValue)),
        )
        .toList(growable: false);
  }

  static double? _optionalNumber(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static DateTime? _timestamp(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';
}
