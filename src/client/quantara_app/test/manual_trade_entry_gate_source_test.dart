import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale account state does not disable manual trade entry', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
    ).readAsStringSync();
    final start = source.indexOf('String? _tradeBlockReason');
    final end = source.indexOf('Future<void> _showManualTrade', start);
    final gate = source.substring(start, end);

    expect(gate, contains('marketDataFresh'));
    expect(gate, contains('entry.validUntil'));
    expect(gate, contains('entry.stopLoss'));
    expect(gate, isNot(contains('autoTradeController.isConnected')));
    expect(gate, isNot(contains('autoTradeController.canStartNewEntry')));
    expect(source, contains('manualTradeController.prepare(entry)'));
    expect(source, contains('startPreflight reconciliation'));
  });
}
