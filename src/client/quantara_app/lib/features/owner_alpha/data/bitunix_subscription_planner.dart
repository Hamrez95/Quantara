import '../domain/bitunix_public_stream_models.dart';

abstract final class BitunixSubscriptionPlanner {
  static const int maximumSubscriptionsPerConnection = 300;

  static List<BitunixSubscriptionShard> build(
    Iterable<BitunixPublicSubscription> subscriptions,
  ) {
    final unique = <String, BitunixPublicSubscription>{};
    for (final subscription in subscriptions) {
      unique[subscription.key] = subscription;
    }
    final ordered = unique.values.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    if (ordered.isEmpty) return const [];

    final shards = <BitunixSubscriptionShard>[];
    for (
      var offset = 0;
      offset < ordered.length;
      offset += maximumSubscriptionsPerConnection
    ) {
      final end = (offset + maximumSubscriptionsPerConnection).clamp(
        0,
        ordered.length,
      );
      shards.add(
        BitunixSubscriptionShard(
          index: shards.length,
          subscriptions: ordered.sublist(offset, end),
        ),
      );
    }
    return List.unmodifiable(shards);
  }
}

final class BitunixOutboundMessageSchedule {
  BitunixOutboundMessageSchedule({
    this.minimumSpacing = const Duration(milliseconds: 200),
  }) {
    if (minimumSpacing < const Duration(milliseconds: 200)) {
      throw ArgumentError.value(
        minimumSpacing,
        'minimumSpacing',
        'Bitunix allows at most five outbound messages per second.',
      );
    }
  }

  final Duration minimumSpacing;
  DateTime? _lastReservationUtc;

  DateTime reserve(DateTime requestedAtUtc) {
    if (!requestedAtUtc.isUtc) {
      throw ArgumentError.value(
        requestedAtUtc,
        'requestedAtUtc',
        'UTC is required.',
      );
    }
    final last = _lastReservationUtc;
    final reserved = last == null ||
            !requestedAtUtc.isBefore(last.add(minimumSpacing))
        ? requestedAtUtc
        : last.add(minimumSpacing);
    _lastReservationUtc = reserved;
    return reserved;
  }

  void reset() => _lastReservationUtc = null;
}
