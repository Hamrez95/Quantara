import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'default Owner Alpha trading UI does not ship Supervisor connection UI',
    () {
      final page = File(
        'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
      ).readAsStringSync();
      final autoTrade = File(
        'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
      ).readAsStringSync();
      final tools = File(
        'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
      ).readAsStringSync();

      expect(page, isNot(contains('read_only_support_session.dart')));
      expect(autoTrade, isNot(contains('_buildSupervisorSupportSessionCard')));
      expect(tools, isNot(contains('Enable ChatGPT access')));
      expect(tools, isNot(contains('Quantara AI Supervisor')));
      expect(tools, isNot(contains('ReadOnlySupportSessionManager')));
      expect(tools, isNot(contains('ReadOnlySupportSessionTransport')));
    },
  );
}
