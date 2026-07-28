import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/owner_alpha_models.dart';

final class PlatformOpportunityStateStore implements OpportunityStateStore {
  const PlatformOpportunityStateStore({
    this._channel = const MethodChannel('quantara/opportunities'),
  });

  final MethodChannel _channel;

  @override
  Future<OpportunityState> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'loadOpportunityState',
      );
      if (value == null) {
        return const OpportunityState();
      }
      return OpportunityState(
        notificationsEnabled: value['notificationsEnabled'] == true,
        takenSetupIds: _stringSet(value['takenSetupIds']),
        notifiedSetupIds: _stringSet(value['notifiedSetupIds']),
        journal: _decodeJournal(value['journalJson']),
      );
    } on PlatformException {
      return const OpportunityState();
    } on MissingPluginException {
      return const OpportunityState();
    }
  }

  @override
  Future<void> save(OpportunityState state) async {
    try {
      await _channel.invokeMethod<void>('saveOpportunityState', {
        'notificationsEnabled': state.notificationsEnabled,
        'takenSetupIds': state.takenSetupIds.toList(growable: false),
        'notifiedSetupIds': state.notifiedSetupIds.toList(growable: false),
        'journalJson': jsonEncode(
          state.journal.map((item) => item.toJson()).toList(growable: false),
        ),
      });
    } on PlatformException {
      // Local journaling must never block market analysis.
    } on MissingPluginException {
      // Tests and non-Android previews intentionally have no native channel.
    }
  }

  static List<SignalJournalEntry> _decodeJournal(Object? value) {
    if (value is! String || value.isEmpty || value.length > 200000) {
      return const [];
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List<Object?>) return const [];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => SignalJournalEntry.tryFromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .whereType<SignalJournalEntry>()
          .take(100)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  static Set<String> _stringSet(Object? value) {
    if (value is! List<Object?>) {
      return const {};
    }
    return value
        .whereType<String>()
        .where((item) => item.isNotEmpty && item.length <= 320)
        .take(250)
        .toSet();
  }
}

final class PlatformSetupNotificationGateway
    implements SetupNotificationGateway {
  const PlatformSetupNotificationGateway({
    this._channel = const MethodChannel('quantara/opportunities'),
  });

  final MethodChannel _channel;

  @override
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> show(TradeIdea idea, {required String languageCode}) async {
    if (!idea.isActionable || idea.targets.length != 3) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('showSetupNotification', {
        'setupId': idea.setupId,
        'symbol': idea.symbol,
        'timeframe': idea.timeframe,
        'direction': idea.direction.name,
        'entryLower': idea.entryLower,
        'entryUpper': idea.entryUpper,
        'stopLoss': idea.stopLoss,
        'targets': idea.targets,
        'leverage': idea.recommendedLeverage,
        'languageCode': languageCode,
      });
    } on PlatformException {
      // Notification delivery is best effort and must not fail a scan.
    } on MissingPluginException {
      // Tests and non-Android previews intentionally have no native channel.
    }
  }
}
