import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('professional strategy and lab have no real-exchange authority', () {
    final root = Directory.current.path;
    final files = [
      'lib/features/owner_alpha/data/professional_strategy_engine.dart',
      'lib/features/owner_alpha/data/professional_portfolio_candidate_adapter.dart',
      'lib/features/owner_alpha/data/trade_idea_factory.dart',
      'lib/features/strategy_lab/data/strategy_lab_runner.dart',
      'lib/features/strategy_lab/domain/strategy_lab_models.dart',
    ];
    final source = files
        .map((path) => File('$root/$path').readAsStringSync())
        .join('\n');

    for (final forbidden in const [
      'BitunixApiCredentials',
      'BitunixLocalLiveApiClient',
      'SecureAutoTradeCredentialsStore',
      'placeOrder(',
      'placeMarketEntry(',
      'placePositionStop(',
      'placePartialTakeProfit(',
      'modifyPositionStop(',
      'cancelOrder(',
      'closePositionReduceOnly(',
      'withdraw(',
      'transfer(',
      '/trade/place_order',
      '/trade/modify_order',
      '/trade/cancel_orders',
      '/assets/withdraw',
      '/assets/transfer',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }

    expect(source, contains('PortfolioEntryCandidate'));
    expect(source, contains('PortfolioRiskPolicy'));
    expect(source, contains('applyPartialFill'));
    expect(source, contains('closePosition'));
    expect(source, contains('dataLeakageDetected'));
  });

  test('strategy decisions are closed-candle and deterministic by source', () {
    final root = Directory.current.path;
    final engine = File(
      '$root/lib/features/owner_alpha/data/professional_strategy_engine.dart',
    ).readAsStringSync();
    final runner = File(
      '$root/lib/features/strategy_lab/data/strategy_lab_runner.dart',
    ).readAsStringSync();
    final adapter = File(
      '$root/lib/features/owner_alpha/data/professional_portfolio_candidate_adapter.dart',
    ).readAsStringSync();

    expect(engine, contains('_closedCandleGate'));
    expect(engine, contains('sha256.convert'));
    expect(engine, contains('candleClosedAt'));
    expect(engine, contains('ExternalContextState.fresh'));
    expect(engine, contains('requireExternalContext'));
    expect(engine, isNot(contains('DateTime.now()')));
    expect(runner, isNot(contains('DateTime.now()')));
    expect(adapter, contains("'strategy-reservation-"));
    expect(adapter, contains("'strategy-journal-"));
  });

  test('all four professional setup kinds remain implemented', () {
    final source = File(
      '${Directory.current.path}/lib/features/owner_alpha/data/professional_strategy_engine.dart',
    ).readAsStringSync();

    for (final required in const [
      'ProfessionalSetupKind.trendPullback',
      'ProfessionalSetupKind.breakoutRetest',
      'ProfessionalSetupKind.arshiaCandle',
      'ProfessionalSetupKind.rangeReversal',
      '_trendPullback(',
      '_breakoutRetest(',
      '_arshiaCandle(',
      '_rangeReversal(',
    ]) {
      expect(source, contains(required));
    }
  });

  test('global canary entry gate requires explicit arm and forbids auto arm', () {
    final source = File(
      '${Directory.current.path}/lib/features/auto_trade/domain/private_account_reconciliation.dart',
    ).readAsStringSync();

    expect(source, contains('static const bool realEntriesAllowed = true;'));
    expect(
      source,
      contains('static const bool explicitUserArmRequired = true;'),
    );
    expect(source, contains('static const bool automaticArmAllowed = false;'));
  });
}
