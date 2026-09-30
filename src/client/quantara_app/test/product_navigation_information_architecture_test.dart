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
    expect(source, isNot(contains('Bot Lab')));
  });

  test('Strategy Lab is absent from the product navigation surface', () {
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(page, isNot(contains('owner_alpha_strategy_lab.dart')));
    expect(page, isNot(contains('strategy_lab/')));
    expect(page, isNot(contains('StrategyLab')));
  });

  test('Portfolio Risk remains a Home action, not a top strip', () {
    final app = File('lib/app/quantara_app.dart').readAsStringSync();
    final home = File(
      'lib/features/owner_alpha/presentation/owner_alpha_home.dart',
    ).readAsStringSync();

    expect(app, isNot(contains('final class _QuantaraHome')));
    expect(app, isNot(contains('height: 44')));
    expect(home, contains('onOpenPortfolioRisk'));
  });

  test('secondary tools remain reachable from Home quick actions', () {
    final home = File(
      'lib/features/owner_alpha/presentation/owner_alpha_home.dart',
    ).readAsStringSync();

    for (final destination in const [1, 2, 3, 5, 6]) {
      expect(home, contains('destination: $destination'));
    }
  });
}
