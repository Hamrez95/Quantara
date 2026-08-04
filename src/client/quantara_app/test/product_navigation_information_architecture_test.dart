import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile navigation exposes only four stable top-level destinations', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(source, contains('const _mobileDestinationIndexes = [0, 1, 5, 7];'));
    expect(
      source,
      contains('const _desktopDestinationIndexes = [0, 1, 2, 3, 5, 6, 7];'),
    );
    expect(source, contains("strings.t('خانه', 'Home')"));
    expect(source, contains('Icons.home_outlined'));
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
    expect(home, contains('کنترل ریسک معاملات'));
    expect(home, contains('این صفحه خودش هیچ سفارشی ارسال نمی‌کند'));
    expect(home, contains('onOpenPortfolioRisk'));
    expect(panel, contains('این صفحه بودجه ریسک را نمایش می‌دهد'));
    expect(panel, contains('شروع ترید واقعی فقط از صفحه ترید خودکار'));
  });

  test('secondary tools remain reachable from Home quick actions', () {
    final home = File(
      'lib/features/owner_alpha/presentation/owner_alpha_home.dart',
    ).readAsStringSync();

    for (final destination in const [1, 2, 3, 5, 6]) {
      expect(home, contains('destination: $destination'));
    }
    expect(home, contains("strings.t('ترید خودکار', 'Auto Trade')"));
    expect(home, contains("strings.t('ژورنال', 'Journal')"));
  });
}
