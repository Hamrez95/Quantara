import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_subscription_planner.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';

void main() {
  group('BitunixSubscriptionPlanner', () {
    test('deduplicates and deterministically shards at 300 channels', () {
      final subscriptions = [
        for (var index = 0; index < 601; index++)
          BitunixPublicSubscription.ticker(
            'S${index.toString().padLeft(4, '0')}USDT',
          ),
      ];
      subscriptions.add(subscriptions.first);

      final shards = BitunixSubscriptionPlanner.build(subscriptions);

      expect(shards, hasLength(3));
      expect(shards[0].subscriptions, hasLength(300));
      expect(shards[1].subscriptions, hasLength(300));
      expect(shards[2].subscriptions, hasLength(1));
      expect(shards[0].subscriptions.first.symbol, 'S0000USDT');
      expect(shards[2].subscriptions.single.symbol, 'S0600USDT');
    });

    test('returns no connections for an empty universe', () {
      expect(BitunixSubscriptionPlanner.build(const []), isEmpty);
    });
  });

  group('BitunixOutboundMessageSchedule', () {
    test('reserves no more than five message slots per second', () {
      final schedule = BitunixOutboundMessageSchedule();
      final now = DateTime.utc(2026, 8, 2, 12);

      final reservations = [
        for (var index = 0; index < 6; index++) schedule.reserve(now),
      ];

      expect(reservations[0], now);
      expect(reservations[1], now.add(const Duration(milliseconds: 200)));
      expect(reservations[4], now.add(const Duration(milliseconds: 800)));
      expect(reservations[5], now.add(const Duration(seconds: 1)));
    });

    test('does not move a naturally spaced request backwards', () {
      final schedule = BitunixOutboundMessageSchedule();
      final first = DateTime.utc(2026, 8, 2, 12);
      final later = first.add(const Duration(seconds: 3));

      expect(schedule.reserve(first), first);
      expect(schedule.reserve(later), later);
    });

    test('rejects a spacing below the official limit', () {
      expect(
        () => BitunixOutboundMessageSchedule(
          minimumSpacing: const Duration(milliseconds: 199),
        ),
        throwsArgumentError,
      );
    });
  });
}
