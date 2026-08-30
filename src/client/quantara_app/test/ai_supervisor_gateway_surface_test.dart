import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI Supervisor gateway exposes analysis only', () {
    final source = File(
      'lib/features/ai_supervisor/domain/supervisor_analysis_gateway.dart',
    ).readAsStringSync();

    expect(source, contains('Future<SupervisorReview> review('));
    expect(source, isNot(contains('placeOrder')));
    expect(source, isNot(contains('cancelOrder')));
    expect(source, isNot(contains('modifyOrder')));
    expect(source, isNot(contains('setLeverage')));
    expect(source, isNot(contains('stopLoss')));
    expect(source, isNot(contains('takeProfit')));
    expect(source, isNot(contains('transfer')));
    expect(source, isNot(contains('riskLimit')));
    expect(source, isNot(contains('updateStrategy')));
  });
}
