import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auto trade uses purposeful visual states with reduced-motion support', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade_support.dart',
    ).readAsStringSync();

    expect(source, contains('MediaQuery.disableAnimationsOf(context)'));
    expect(source, contains('_SecureConnectionIllustration'));
    expect(source, contains('_CompactEmptyState'));
    expect(source, contains('AnimatedSwitcher'));
    expect(source, isNot(contains('AnimationController(')));
    expect(source, isNot(contains('Image.network(')));
  });
}
