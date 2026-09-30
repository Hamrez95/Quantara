import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile navigation exposes four stable top-level destinations', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(source, contains('const _mobileDestinationIndexes = [0, 1, 5, 7];'));
    expect(
      source,
      contains('const _desktopDestinationIndexes = [0, 1, 2, 3, 5, 6, 7];'),
    );
    expect(source, contains("strings.t('Ø®Ø§ÙÙ', 'Home')"));
    expect(source, contains('Icons.home_outlined'));
    expect(source, isNot(contains('Ø¢Ø²ÙØ§ÛØ´Ú¯Ø§Ù')));
  });

  test('Strategy Lab is absent from the product navigation surface', () {
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(page, isNot(contains("part 'owner_alpha_strategy_lab.dart'")));
    expect(page, isNot(contains("import '../../strategy_lab/")));
    expect(page, isNot(contains('onOpenStrategyLab')));
    expect(page, isNot(contains('openStrategyLab')));
    expect(page, isNot(contains('strings.strategyLab')));
    expect(page, isNot(contains('_StrategyLabView(')));
  });

  test('Portfolio Risk is explained inside Home instead of a top strip', () {
    final app = File('lib/app/quantara_app.dart').readAsStringSync();
    final home = File(
      'lib/features/owner_alpha/presentation/owner_alpha_home.dart',
    ).readAsStringSync();
    final panel = File(
      'lib/features/portfolio_risk/presentation/portfolio_risk_panel.dart',
    ).readAsStringSync();

    expect(app, isNot(contains('final class _QuantaraHome')));
    expect(app, isNot(contains('height: 44')));
    expect(home, contains('Ú©ÙØªØ±Ù Ø±ÛØ³Ú© ÙØ¹Ø§ÙÙØ§Øª'));
    expect(home, contains('Ø§ÛÙ ØµÙØ­Ù Ø®ÙØ¯Ø´ ÙÛÚ Ø³ÙØ§Ø±Ø´Û Ø§Ø±Ø³Ø§Ù ÙÙÛâÚ©ÙØ¯'));
    expect(home, contains('onOpenPortfolioRisk'));
    expect(panel, contains('Ø§ÛÙ ØµÙØ­Ù Ø¨ÙØ¯Ø¬Ù Ø±ÛØ³Ú© Ø±Ø§ ÙÙØ§ÛØ´ ÙÛâØ¯ÙØ¯'));
    expect(panel, contains('Ø´Ø±ÙØ¹ ØªØ±ÛØ¯ ÙØ§ÙØ¹Û ÙÙØ· Ø§Ø² ØµÙØ­Ù ØªØ±ÛØ¯ Ø®ÙØ¯Ú©Ø§Ø±'));
  });

  test('secondary tools remain reachable from Home quick actions', () {
    final home = File(
      'lib/features/owner_alpha/presentation/owner_alpha_home.dart',
    ).readAsStringSync();

    for (final destination in const [1, 2, 3, 5, 6]) {
      expect(home, contains('destination: $destination'));
    }
    expect(home, contains("strings.t('ØªØ±ÛØ¯ Ø®ÙØ¯Ú©Ø§Ø±', 'Auto Trade')"));
    expect(home, contains("strings.t('ÚÙØ±ÙØ§Ù', 'Journal')"));
  });
}
