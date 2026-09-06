import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard exposes persisted setup outcomes as a read-only summary', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_dashboard.dart',
    ).readAsStringSync();

    expect(source, contains('class _RecentSetupDecisionsCard'));
    expect(source, contains('DurableCandidateAuditStore'));
    expect(source, contains('Recent setup decisions'));
    expect(source, contains('This report never places an order'));
    expect(source, contains('OpportunityTransitionReason.priceRanAway'));
    expect(source, contains('OpportunityTransitionReason.dataStale'));
  });
}
