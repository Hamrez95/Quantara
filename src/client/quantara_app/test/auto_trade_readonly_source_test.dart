import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Auto Trade separates locked server mode from guarded local live', () {
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    final view = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    final readOnlyClient = File(
      'lib/features/auto_trade/data/bitunix_private_api_client.dart',
    ).readAsStringSync();
    final localClient = File(
      'lib/features/auto_trade/data/bitunix_local_live_api_client.dart',
    ).readAsStringSync();
    final localController = File(
      'lib/features/auto_trade/application/local_live_trade_controller.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(page, contains("part 'owner_alpha_auto_trade.dart';"));
    expect(page, contains("part 'owner_alpha_auto_trade_support.dart';"));
    expect(page, contains("'ترید خودکار'"));
    expect(view, contains('ترید واقعی محلی'));
    expect(view, contains('شروع ترید'));
    expect(view, contains('قطع ترید'));
    expect(view, contains('ترید شبانه سروری · قفل'));
    expect(view, contains('No server Start action works'));
    expect(readOnlyClient, contains('/api/v1/futures/account'));
    expect(readOnlyClient, isNot(contains('/trade/place_order')));
    expect(localClient, contains('/api/v1/futures/trade/place_order'));
    expect(localClient, contains('reduceOnly'));
    expect(localController, contains('autoRunOnBoot: false'));
    expect(localController, contains('autoRunOnMyPackageReplaced: false'));
    expect(localController, contains('ForegroundServiceTypes.specialUse'));
    expect(manifest, contains('FOREGROUND_SERVICE_SPECIAL_USE'));
    expect(manifest, contains('foregroundServiceType="specialUse"'));
    expect(localClient, isNot(contains('withdraw')));
    expect(localClient, isNot(contains('transfer')));
  });
}
