import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/read_only_support_session.dart';

void main() {
  test('support session is default off, read-only, expiring and revocable', () {
    var now = DateTime.utc(2026, 8, 8, 8);
    final manager = ReadOnlySupportSessionManager(
      clock: () => now,
      random: Random(7),
    );
    expect(manager.isActive, isFalse);
    final descriptor = ReadOnlySupportSessionManager.architectureDescriptor();
    expect(descriptor['defaultEnabled'], isFalse);
    expect(descriptor['tradingWritesAllowed'], isFalse);
    expect(descriptor['exchangeCredentialsAllowed'], isFalse);

    final grant = manager.enable();
    expect(grant.scope, 'diagnostics.read');
    expect(grant.expiresAt, now.add(const Duration(minutes: 45)));
    expect(grant.token.length, greaterThan(30));
    final diagnostic = manager.current!.toDiagnosticJson(now);
    expect(diagnostic.toString(), isNot(contains(grant.token)));
    expect(diagnostic['tradingPermission'], isFalse);

    now = now.add(const Duration(minutes: 46));
    expect(manager.isActive, isFalse);

    now = DateTime.utc(2026, 8, 8, 9);
    manager.enable(ttl: const Duration(minutes: 30));
    expect(manager.isActive, isTrue);
    manager.revoke();
    expect(manager.isActive, isFalse);
  });

  test('support TTL outside 30-60 minute boundary is rejected', () {
    final manager = ReadOnlySupportSessionManager(random: Random(1));
    expect(
      () => manager.enable(ttl: const Duration(minutes: 29)),
      throwsArgumentError,
    );
    expect(
      () => manager.enable(ttl: const Duration(minutes: 61)),
      throwsArgumentError,
    );
  });
}
