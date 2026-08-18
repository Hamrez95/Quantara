import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/owner_alpha_models.dart';

const opportunityNotificationsEnabledKey =
    'quantara.opportunities.notifications-enabled';
const opportunityTakenSetupIdsKey = 'quantara.opportunities.taken-setup-ids';
const opportunityNotifiedSetupIdsKey =
    'quantara.opportunities.notified-setup-ids';
const opportunityJournalKey = 'quantara.opportunities.journal-json';
const opportunityLastBackgroundScanKey =
    'quantara.opportunities.last-background-scan';
const opportunityLastBackgroundErrorKey =
    'quantara.opportunities.last-background-error';

final class PlatformOpportunityStateStore implements OpportunityStateStore {
  const PlatformOpportunityStateStore({
    this._channel = const MethodChannel('quantara/opportunities'),
  });

  final MethodChannel _channel;

  @override
  Future<OpportunityState> load() async {
    final preferences = SharedPreferencesAsync();
    try {
      final sharedJournal = await preferences.getString(opportunityJournalKey);
      final sharedEnabled = await preferences.getBool(
        opportunityNotificationsEnabledKey,
      );
      if (sharedJournal != null || sharedEnabled != null) {
        return OpportunityState(
          notificationsEnabled: sharedEnabled ?? false,
          takenSetupIds:
              (await preferences.getStringList(opportunityTakenSetupIdsKey) ??
                      const <String>[])
                  .toSet(),
          notifiedSetupIds:
              (await preferences.getStringList(
                        opportunityNotifiedSetupIdsKey,
                      ) ??
                      const <String>[])
                  .toSet(),
          journal: decodeSignalJournal(sharedJournal),
          lastBackgroundScanAt: DateTime.tryParse(
            await preferences.getString(opportunityLastBackgroundScanKey) ?? '',
          )?.toUtc(),
          lastBackgroundError: await preferences.getString(
            opportunityLastBackgroundErrorKey,
          ),
        );
      }

      // One-time migration from the native preview store so existing journal
      // entries survive the switch to storage shared with the background
      // isolate.
      final value = await _channel.invokeMapMethod<String, Object?>(
        'loadOpportunityState',
      );
      if (value == null) {
        return const OpportunityState();
      }
      final migrated = OpportunityState(
        notificationsEnabled: value['notificationsEnabled'] == true,
        takenSetupIds: _stringSet(value['takenSetupIds']),
        notifiedSetupIds: _stringSet(value['notifiedSetupIds']),
        journal: decodeSignalJournal(value['journalJson']),
      );
      await _saveShared(preferences, migrated);
      return migrated;
    } on PlatformException {
      return const OpportunityState();
    } on MissingPluginException {
      return const OpportunityState();
    }
  }

  @override
  Future<void> save(OpportunityState state) async {
    await _saveShared(SharedPreferencesAsync(), state);
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

  static Future<void> _saveShared(
    SharedPreferencesAsync preferences,
    OpportunityState state,
  ) async {
    await preferences.setBool(
      opportunityNotificationsEnabledKey,
      state.notificationsEnabled,
    );
    await preferences.setStringList(
      opportunityTakenSetupIdsKey,
      state.takenSetupIds.take(250).toList(growable: false),
    );
    await preferences.setStringList(
      opportunityNotifiedSetupIdsKey,
      state.notifiedSetupIds.take(250).toList(growable: false),
    );
    await preferences.setString(
      opportunityJournalKey,
      encodeSignalJournal(state.journal),
    );
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

String encodeSignalJournal(Iterable<SignalJournalEntry> journal) => jsonEncode(
  journal.take(100).map((item) => item.toJson()).toList(growable: false),
);

List<SignalJournalEntry> decodeSignalJournal(Object? value) {
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

final class PlatformSetupNotificationGateway
    implements SetupNotificationGateway {
  const PlatformSetupNotificationGateway({
    this._channel = const MethodChannel('quantara/opportunities'),
  });

  final MethodChannel _channel;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final StreamController<String> _openedSetupIds =
      StreamController<String>.broadcast();
  static Future<void>? _notificationInitialization;

  static Future<void> _ensureInitialized() {
    return _notificationInitialization ??= _initializeNotifications();
  }

  static Future<void> _initializeNotifications() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_quantara_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final setupId = _validSetupId(response.payload);
        if (setupId != null) _openedSetupIds.add(setupId);
      },
    );
  }

  @override
  Stream<String> get openedSetupIds => _openedSetupIds.stream;

  @override
  Future<String?> initialSetupId() async {
    try {
      await _ensureInitialized();
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp != true) return null;
      return _validSetupId(launch?.notificationResponse?.payload);
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _ensureInitialized();
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) {
        return false;
      }
      return await android.requestNotificationsPermission() ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> openBackgroundSettings() async {
    try {
      await _channel.invokeMethod<void>('openBackgroundSettings');
    } on PlatformException {
      // Some Android variants do not expose an app-specific settings page.
    } on MissingPluginException {
      // Non-Android previews intentionally have no native channel.
    }
  }

  @override
  Future<void> show(TradeIdea idea, {required String languageCode}) async {
    if (!idea.isActionable || idea.targets.length != 3) {
      return;
    }
    try {
      await _ensureInitialized();
      final persian = languageCode != 'en';
      final direction = persian
          ? (idea.direction == TradeDirection.long ? 'خرید' : 'فروش')
          : idea.direction.name.toUpperCase();
      final title = persian
          ? 'ستاپ $direction · ${idea.symbol} · ${idea.timeframe}'
          : '$direction setup · ${idea.symbol} · ${idea.timeframe}';
      final body = persian
          ? 'ورود ${idea.entryLower}–${idea.entryUpper} | SL ${idea.stopLoss} | TP ${idea.targets.join(' / ')} | اهرم ${idea.recommendedLeverage}x'
          : 'Entry ${idea.entryLower}–${idea.entryUpper} | SL ${idea.stopLoss} | TP ${idea.targets.join(' / ')} | ${idea.recommendedLeverage}x';
      await _notifications.show(
        id: _stableNotificationId(idea.setupId),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'quantara_setup_alerts_v1',
            'Quantara setups',
            channelDescription: 'New paper-trading setup alerts after a scan',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.recommendation,
            actions: [
              AndroidNotificationAction(
                'view_analysis',
                persian ? 'مشاهده تحلیل' : 'View analysis',
                showsUserInterface: true,
              ),
            ],
          ),
        ),
        payload: idea.setupId,
      );
    } on Object {
      // Notification delivery is best effort and must not fail a scan.
    }
  }
}

String? _validSetupId(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty || normalized.length > 320) return null;
  return normalized;
}

int _stableNotificationId(String value) {
  var hash = 17;
  for (final unit in value.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return hash;
}
