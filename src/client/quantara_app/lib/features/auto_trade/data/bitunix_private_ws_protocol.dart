import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/auto_trade_models.dart';
import '../domain/private_truth_models.dart';

abstract final class BitunixPrivateWsProtocol {
  static final Uri endpoint = Uri.parse('wss://fapi.bitunix.com/private/');
  static const int maximumClientMessagesPerSecond = 5;
  static const List<String> channels = ['balance', 'position', 'order', 'tpsl'];

  static Map<String, Object?> loginFrame({
    required BitunixApiCredentials credentials,
    required String nonce,
    required int unixSeconds,
  }) {
    final first = sha256
        .convert(utf8.encode('$nonce$unixSeconds${credentials.apiKey}'))
        .toString();
    final sign = sha256
        .convert(utf8.encode('$first${credentials.secretKey}'))
        .toString();
    return {
      'op': 'login',
      'args': [
        {
          'apiKey': credentials.apiKey,
          'timestamp': unixSeconds,
          'nonce': nonce,
          'sign': sign,
        },
      ],
    };
  }

  static Map<String, Object?> subscriptionFrame() => {
    'op': 'subscribe',
    'args': [
      for (final channel in channels) {'ch': channel},
    ],
  };

  static Map<String, Object?> pingFrame(int unixSeconds) => {
    'op': 'ping',
    'ping': unixSeconds,
  };

  static PrivateTruthEvent? parsePush({
    required Object? decoded,
    required DateTime receivedAtUtc,
    required DateTime processedAtUtc,
  }) {
    if (decoded is! Map<String, Object?>) return null;
    final channelRaw = _string(decoded['ch']).toLowerCase();
    final channel = switch (channelRaw) {
      'balance' => PrivateTruthChannel.balance,
      'order' => PrivateTruthChannel.order,
      'position' => PrivateTruthChannel.position,
      'tpsl' => PrivateTruthChannel.tpsl,
      _ => null,
    };
    if (channel == null) return null;
    final data = decoded['data'];
    if (data is! Map<String, Object?>) return null;
    final exchangeTimestamp = _timestamp(decoded['ts']);
    if (exchangeTimestamp == null) return null;
    final payload = switch (channel) {
      PrivateTruthChannel.balance => _balance(data),
      PrivateTruthChannel.order => _order(data),
      PrivateTruthChannel.position => _position(data),
      PrivateTruthChannel.tpsl => _protection(data),
    };
    if (payload == null) return null;
    final eventIdentity = _eventIdentity(
      channel: channel,
      exchangeTimestamp: exchangeTimestamp,
      payload: payload,
    );
    return PrivateTruthEvent(
      eventIdentity: eventIdentity,
      channel: channel,
      exchangeTimestampUtc: exchangeTimestamp,
      receivedAtUtc: receivedAtUtc.toUtc(),
      processedAtUtc: processedAtUtc.toUtc(),
      payload: payload,
    );
  }

  static PrivateBalanceUpdate? _balance(Map<String, Object?> data) {
    final coin = _string(data['coin']).toUpperCase();
    if (coin.isEmpty) return null;
    return PrivateBalanceUpdate(
      coin: coin,
      available: _number(data['available']),
      frozen: _number(data['frozen']),
      margin: _number(data['margin']),
      isolationFrozen: _number(data['isolationFrozen']),
      crossFrozen: _number(data['crossFrozen']),
      isolationMargin: _number(data['isolationMargin']),
      crossMargin: _number(data['crossMargin']),
    );
  }

  static PrivateOrderUpdate? _order(Map<String, Object?> data) {
    final orderId = _string(data['orderId']);
    final symbol = _string(data['symbol']).toUpperCase();
    if (orderId.isEmpty || symbol.isEmpty) return null;
    return PrivateOrderUpdate(
      event: _string(data['event'], fallback: 'UPDATE').toUpperCase(),
      orderId: orderId,
      clientId: _string(data['clientId']),
      symbol: symbol,
      side: _string(data['side']).toUpperCase(),
      orderType: _string(data['type']).toUpperCase(),
      orderStatus: _string(
        data['orderStatus'],
        fallback: _string(data['status'], fallback: 'UNKNOWN'),
      ).toUpperCase(),
      quantity: _number(data['qty']),
      dealAmount: _number(data['dealAmount']),
      averagePrice: _number(data['averagePrice']),
      fee: _number(data['fee']),
      updatedAtUtc: _timestamp(data['mtime']),
    );
  }

  static PrivatePositionUpdate? _position(Map<String, Object?> data) {
    final positionId = _string(data['positionId']);
    final symbol = _string(data['symbol']).toUpperCase();
    if (positionId.isEmpty || symbol.isEmpty) return null;
    return PrivatePositionUpdate(
      event: _string(data['event'], fallback: 'UPDATE').toUpperCase(),
      positionId: positionId,
      symbol: symbol,
      side: _string(data['side']).toUpperCase(),
      marginMode: _string(data['marginMode']).toUpperCase(),
      positionMode: _string(data['positionMode']).toUpperCase(),
      leverage: _integer(data['leverage']),
      margin: _number(data['margin']),
      quantity: _number(data['qty']),
      realizedPnl: _number(data['realizedPNL']),
      unrealizedPnl: _number(data['unrealizedPNL']),
      funding: _number(data['funding']),
      fee: _number(data['fee']),
    );
  }

  static PrivateProtectionUpdate? _protection(Map<String, Object?> data) {
    final orderId = _string(data['orderId']);
    final positionId = _string(data['positionId']);
    final symbol = _string(data['symbol']).toUpperCase();
    if (orderId.isEmpty || positionId.isEmpty || symbol.isEmpty) return null;
    return PrivateProtectionUpdate(
      event: _string(data['event'], fallback: 'UPDATE').toUpperCase(),
      orderId: orderId,
      positionId: positionId,
      symbol: symbol,
      status: _string(data['status'], fallback: 'UNKNOWN').toUpperCase(),
      takeProfitQuantity: _optionalNumber(data['tpQty']),
      takeProfitPrice: _optionalNumber(data['tpPrice']),
      stopLossQuantity: _optionalNumber(data['slQty']),
      stopLossPrice: _optionalNumber(data['slPrice']),
    );
  }

  static String _eventIdentity({
    required PrivateTruthChannel channel,
    required DateTime exchangeTimestamp,
    required PrivateTruthPayload payload,
  }) {
    final stablePieces = switch (payload) {
      PrivateBalanceUpdate balance => [
        balance.resourceIdentity,
        balance.available,
        balance.frozen,
        balance.margin,
      ],
      PrivateOrderUpdate order => [
        order.resourceIdentity,
        order.event,
        order.orderStatus,
        order.dealAmount,
        order.averagePrice,
        order.fee,
      ],
      PrivatePositionUpdate position => [
        position.resourceIdentity,
        position.event,
        position.quantity,
        position.realizedPnl,
        position.unrealizedPnl,
        position.funding,
        position.fee,
      ],
      PrivateProtectionUpdate protection => [
        protection.resourceIdentity,
        protection.event,
        protection.status,
        protection.takeProfitQuantity,
        protection.takeProfitPrice,
        protection.stopLossQuantity,
        protection.stopLossPrice,
      ],
    };
    final canonical = jsonEncode([
      channel.name,
      exchangeTimestamp.microsecondsSinceEpoch,
      ...stablePieces,
    ]);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static DateTime? _timestamp(Object? value) {
    final raw = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (raw == null || raw <= 0) return null;
    final milliseconds = raw < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _number(Object? value) => _optionalNumber(value) ?? 0;

  static double? _optionalNumber(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static int _integer(Object? value) {
    if (value is num) return max(0, value.toInt());
    return max(0, int.tryParse(value?.toString() ?? '') ?? 0);
  }
}
