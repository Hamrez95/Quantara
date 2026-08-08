import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Local Live main card delegates configuration to a gear sheet', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    expect(source, contains('_buildLocalLiveConfigurationSummary'));
    expect(source, isNot(contains("_t('نمادهای مجاز', 'Allowed symbols')")));
    expect(source, contains('_enabledStrategies'));
    expect(source, contains('strategies: _enabledStrategies.toList'));
  });

  test('settings sheet exposes strategies and diagnostic export', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
    ).readAsStringSync();
    expect(source, contains('Icons.settings_rounded'));
    expect(source, contains('_showLocalLiveSettings'));
    expect(source, contains('CheckboxListTile'));
    expect(source, contains('for (final strategy in AnalysisStrategy.values)'));
    expect(source, contains('.recommendedStrategies'));
    expect(source, contains('SharePlus.instance.share'));
    expect(source, contains('LocalLiveDiagnosticBundle.encode'));
    expect(source, contains('managed.timeframe'));
    expect(source, contains('Unknown timeframe'));
  });

  test('support export is user initiated and never reads secure credentials', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
    ).readAsStringSync();
    expect(source, contains("label: Text(_t('خروجی JSON', 'Export JSON'))"));
    expect(source, isNot(contains('SecureAutoTradeCredentialsStore')));
    expect(source, isNot(contains("getData<String>(key: 'api")));
  });
}
