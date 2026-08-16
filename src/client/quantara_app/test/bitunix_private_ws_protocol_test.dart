import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_ws_protocol.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  test('login signature matches the official two-stage SHA256 contract', () {
    const credentials = BitunixApiCredentials(
      apiKey: 'api-key',
      secretKey: 'secret-key',
    );
    const nonce = 'nonce-123';
    const timestamp = 1786800000;
    final digest = sha256
        .convert(utf8.encode('$nonce$timestamp${credentials.apiKey}'))
        .toString();
    final expected = sha256
        .convert(utf8.encode('$digest${credentials.secretKey}'))
        .toString();

    final frame = BitunixPrivateWsProtocol.loginFrame(
      credentials: credentials,
      nonce: nonce,
      unixSeconds: timestamp,
    );
    final args =
        (frame['args']! as List<Object?>).single as Map<String, Object?>;

    expect(frame['op'], 'login');
    expect(args['apiKey'], credentials.apiKey);
    expect(args['timestamp'], timestamp);
    expect(args['nonce'], nonce);
    expect(args['sign'], expected);
    expect(jsonEncode(frame), isNot(contains(credentials.secretKey)));
  });

  test('subscription stays within official private-channel contract', () {
    final frame = BitunixPrivateWsProtocol.subscriptionFrame();
    final args = frame['args']! as List<Object?>;

    expect(
      BitunixPrivateWsProtocol.endpoint.toString(),
      'wss://fapi.bitunix.com/private/',
    );
    expect(BitunixPrivateWsProtocol.maximumClientMessagesPerSecond, 5);
    expect(args.map((item) => (item as Map<String, Object?>)['ch']), [
      'balance',
      'position',
      'order',
      'tpsl',
    ]);
  });

  test('order push parses exchange timestamp and terminal fill truth', () {
    final received = DateTime.utc(2026, 8, 15, 12, 0, 1);
    final event = BitunixPrivateWsProtocol.parsePush(
      decoded: <String, Object?>{
        'ch': 'order',
        'ts': 1786795200123,
        'data': <String, Object?>{
          'event': 'UPDATE',
          'orderId': 'ord-1',
          'clientId': 'client-1',
          'symbol': 'BTCUSDT',
          'side': 'BUY',
          'type': 'MARKET',
          'orderStatus': 'FILLED',
          'qty': '0.01',
          'dealAmount': '0.01',
          'averagePrice': '120000',
          'fee': '0.72',
          'mtime': 1786795200120,
        },
      },
      receivedAtUtc: received,
      processedAtUtc: received.add(const Duration(milliseconds: 5)),
    );

    expect(event, isNotNull);
    expect(event!.channel, PrivateTruthChannel.order);
    final order = event.payload as PrivateOrderUpdate;
    expect(order.orderId, 'ord-1');
    expect(order.orderStatus, 'FILLED');
    expect(order.isTerminal, isTrue);
    expect(order.averagePrice, 120000);
    expect(order.dealAmount, 0.01);
    expect(event.eventIdentity, hasLength(64));
  });

  test('position and TPSL pushes preserve exchange-confirmed facts', () {
    final now = DateTime.utc(2026, 8, 15, 12);
    final position = BitunixPrivateWsProtocol.parsePush(
      decoded: <String, Object?>{
        'ch': 'position',
        'ts': 1786795200000,
        'data': <String, Object?>{
          'event': 'UPDATE',
          'positionId': 'pos-1',
          'symbol': 'ETHUSDT',
          'side': 'LONG',
          'marginMode': 'ISOLATION',
          'positionMode': 'ONE_WAY',
          'leverage': '3',
          'margin': '50',
          'qty': '0.1',
          'realizedPNL': '1.2',
          'unrealizedPNL': '2.5',
          'funding': '-0.03',
          'fee': '0.2',
        },
      },
      receivedAtUtc: now,
      processedAtUtc: now,
    );
    final protection = BitunixPrivateWsProtocol.parsePush(
      decoded: <String, Object?>{
        'ch': 'tpsl',
        'ts': 1786795200001,
        'data': <String, Object?>{
          'event': 'UPDATE',
          'orderId': 'sl-1',
          'positionId': 'pos-1',
          'symbol': 'ETHUSDT',
          'status': 'ACTIVE',
          'slQty': '0.1',
          'slPrice': '3000',
          'tpQty': '0.05',
          'tpPrice': '3300',
        },
      },
      receivedAtUtc: now,
      processedAtUtc: now,
    );

    final p = position!.payload as PrivatePositionUpdate;
    final sl = protection!.payload as PrivateProtectionUpdate;
    expect(p.funding, -0.03);
    expect(p.fee, 0.2);
    expect(p.closed, isFalse);
    expect(sl.stopLossPrice, 3000);
    expect(sl.takeProfitPrice, 3300);
  });

  test('unknown/malformed pushes fail closed instead of inventing truth', () {
    final now = DateTime.utc(2026, 8, 15, 12);
    expect(
      BitunixPrivateWsProtocol.parsePush(
        decoded: <String, Object?>{
          'ch': 'mystery',
          'ts': 1,
          'data': <String, Object?>{},
        },
        receivedAtUtc: now,
        processedAtUtc: now,
      ),
      isNull,
    );
    expect(
      BitunixPrivateWsProtocol.parsePush(
        decoded: <String, Object?>{'ch': 'order', 'data': <String, Object?>{}},
        receivedAtUtc: now,
        processedAtUtc: now,
      ),
      isNull,
    );
  });
}
