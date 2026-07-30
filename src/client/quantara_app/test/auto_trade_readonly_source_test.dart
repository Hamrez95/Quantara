import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Auto Trade is a separate read-only workspace', () {
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    final view = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    final client = File(
      'lib/features/auto_trade/data/bitunix_private_api_client.dart',
    ).readAsStringSync();
    expect(page, contains("part 'owner_alpha_auto_trade.dart';"));
    expect(page, contains("'ترید خودکار'"));
    expect(view, contains('نسخه 0.12A فقط خواندنی است'));
    expect(view, isNot(contains('place_order')));
    expect(client, contains('/api/v1/futures/account'));
    expect(client, contains('/get_pending_positions'));
    expect(client, contains('/get_pending_orders'));
    expect(client, isNot(contains('/trade/place_order')));
  });
}
