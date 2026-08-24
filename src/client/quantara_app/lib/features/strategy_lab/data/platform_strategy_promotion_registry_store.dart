import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/strategy_promotion_registry.dart';

abstract interface class StrategyPromotionRegistryStore {
  Future<StrategyPromotionRegistry> load();

  Future<void> save(StrategyPromotionRegistry registry);
}

abstract final class StrategyPromotionRegistryCodec {
  static const schemaVersion = 1;
  static const maximumEvents = 4096;

  static String encode(StrategyPromotionRegistry registry) {
    if (registry.events.length > maximumEvents) {
      throw StateError('Promotion registry exceeds the durable event bound.');
    }
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'events': registry.events
          .map((event) => event.toJson())
          .toList(growable: false),
    });
  }

  static StrategyPromotionRegistry decode(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported promotion registry snapshot.');
    }
    final rawEvents = decoded['events'];
    if (rawEvents is! List || rawEvents.length > maximumEvents) {
      throw const FormatException('Invalid promotion registry event history.');
    }
    final events = rawEvents
        .map((raw) {
          if (raw is! Map ||
              raw['schemaVersion'] !=
                  StrategyPromotionRegistryEvent.schemaVersion) {
            throw const FormatException('Invalid promotion registry event.');
          }
          return StrategyPromotionRegistryEvent.fromJson(
            Map<String, Object?>.from(raw),
          );
        })
        .toList(growable: false);
    return StrategyPromotionRegistry.restore(events);
  }
}

final class PlatformStrategyPromotionRegistryStore
    implements StrategyPromotionRegistryStore {
  const PlatformStrategyPromotionRegistryStore();

  static const _key = 'quantara.strategy-promotion.registry-v1';

  @override
  Future<StrategyPromotionRegistry> load() async {
    final preferences = SharedPreferencesAsync();
    final payload = await preferences.getString(_key);
    if (payload == null) return StrategyPromotionRegistry.empty();
    return StrategyPromotionRegistryCodec.decode(payload);
  }

  @override
  Future<void> save(StrategyPromotionRegistry registry) async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      _key,
      StrategyPromotionRegistryCodec.encode(registry),
    );
  }
}
