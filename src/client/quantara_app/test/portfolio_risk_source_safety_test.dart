import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'portfolio risk feature has no exchange mutation or credential authority',
    () {
      final root = Directory.current.path;
      final feature = Directory('$root/lib/features/portfolio_risk');
      final sources = feature
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      final imports = RegExp(r"import\s+'([^']+)'")
          .allMatches(sources)
          .map((match) => match.group(1) ?? '')
          .toList(growable: false);
      for (final importPath in imports) {
        for (final forbidden in const [
          'bitunix_local_live_api_client',
          'secure_auto_trade_credentials_store',
          'auto_trade_credentials',
          'credential_store',
        ]) {
          expect(importPath, isNot(contains(forbidden)));
        }
      }

      for (final forbiddenAuthority in const [
        'BitunixApiCredentials',
        'BitunixLocalLiveApiClient',
        'placeOrder(',
        'placeMarketEntry(',
        'placePositionStop(',
        'placePartialTakeProfit(',
        'modifyPositionStop(',
        'cancelOrder(',
        'cancelEntryOrder(',
        'closePositionReduceOnly(',
        'withdraw(',
        'transfer(',
        'flash_close_position',
        '/trade/place_order',
        '/trade/modify_order',
        '/trade/cancel_orders',
        '/assets/withdraw',
        '/assets/transfer',
      ]) {
        expect(sources, isNot(contains(forbiddenAuthority)));
      }

      expect(sources, contains('liveExecutionAllowed: false'));
      expect(sources, contains("marginMode.toLowerCase() != 'isolated'"));
      expect(sources, contains('PortfolioReservationLifecycle.ambiguous'));
      expect(sources, contains('QuantaraDurableCategory.managedPositions'));
    },
  );

  test('global canary entry gate requires explicit arm and forbids auto arm', () {
    final source = File(
      '${Directory.current.path}/lib/features/auto_trade/domain/private_account_reconciliation.dart',
    ).readAsStringSync();

    expect(source, contains('static const bool realEntriesAllowed = true;'));
    expect(source, contains('static const bool explicitUserArmRequired = true;'));
    expect(source, contains('static const bool automaticArmAllowed = false;'));
  });

  test('portfolio durable payload defines no secret-like keys', () {
    final root = Directory.current.path;
    final files = [
      'lib/features/portfolio_risk/domain/portfolio_risk_models.dart',
      'lib/features/portfolio_risk/domain/portfolio_risk_transitions.dart',
      'lib/features/portfolio_risk/data/portfolio_risk_ledger_store.dart',
    ];
    final source = files
        .map((path) => File('$root/$path').readAsStringSync())
        .join('\n')
        .toLowerCase();

    for (final forbiddenKey in const [
      "'apikey'",
      "'secretkey'",
      "'credential'",
      "'password'",
      "'accesstoken'",
    ]) {
      expect(source, isNot(contains(forbiddenKey)));
    }
  });
}
