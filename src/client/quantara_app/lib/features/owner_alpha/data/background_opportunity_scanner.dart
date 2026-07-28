import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../domain/owner_alpha_models.dart';
import 'bitunix_owner_alpha_repository.dart';
import 'trade_idea_factory.dart';

const _backgroundTask = 'quantara.opportunity-scan.v1';
const _backgroundUniqueName = 'quantara-periodic-opportunity-scan';
const _backgroundNotifiedKey = 'quantara.background.notified-setup-ids';

@pragma('vm:entry-point')
void quantaraBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _backgroundTask || inputData == null) {
      return true;
    }
    WidgetsFlutterBinding.ensureInitialized();
    final symbols = (inputData['symbols'] as List<Object?>?)
            ?.whereType<String>()
            .take(12)
            .toList(growable: false) ??
        const <String>[];
    final capital = (inputData['capital'] as num?)?.toDouble();
    final risk = (inputData['riskPercent'] as num?)?.toDouble();
    if (symbols.isEmpty || capital == null || risk == null) {
      return false;
    }
    final strategy = AnalysisStrategy.values.firstWhere(
      (item) => item.name == inputData['strategy'],
      orElse: () => AnalysisStrategy.structureZones,
    );
    final cadence = SignalCadence.values.firstWhere(
      (item) => item.name == inputData['cadence'],
      orElse: () => SignalCadence.balanced,
    );
    final language = inputData['languageCode'] == 'en' ? 'en' : 'fa';
    final client = http.Client();
    try {
      final repository = BitunixOwnerAlphaRepository(client: client);
      final snapshot = await repository.scan(
        symbols: symbols,
        selectedSymbol: symbols.first,
        selectedTimeframe: '1h',
        capital: capital,
        riskPercent: risk,
        languageCode: language,
      );
      final ideas = <TradeIdea>[
        for (final result in snapshot.radar)
          for (final entry in result.analysesByTimeframe.entries)
            if (BitunixOwnerAlphaRepository.opportunityTimeframes
                .contains(entry.key))
              TradeIdeaFactory.create(
                analysis: entry.value,
                capital: capital,
                riskPercent: risk,
                languageCode: language,
                strategy: strategy,
                cadence: cadence,
                confluence: {
                  for (final direction
                      in result.analysesByTimeframe.entries)
                    direction.key: direction.value.direction,
                },
              ),
      ].where((idea) => idea.isActionable).toList(growable: false);
      if (ideas.isEmpty) {
        return true;
      }

      final preferences = SharedPreferencesAsync();
      final notified = (await preferences.getStringList(
                _backgroundNotifiedKey,
              ) ??
              const <String>[])
          .toSet();
      final notifications = FlutterLocalNotificationsPlugin();
      await notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher'),
        ),
      );
      var changed = false;
      for (final idea in ideas) {
        if (!notified.add(idea.setupId)) {
          continue;
        }
        changed = true;
        final direction = language == 'en'
            ? (idea.direction == TradeDirection.long ? 'Long' : 'Short')
            : (idea.direction == TradeDirection.long ? 'خرید' : 'فروش');
        final title = language == 'en'
            ? '${idea.symbol} · $direction · ${idea.timeframe}'
            : '${idea.symbol} · $direction · ${idea.timeframe}';
        final localExpiry = idea.validUntil.toLocal();
        final minute = localExpiry.minute.toString().padLeft(2, '0');
        final body = language == 'en'
            ? 'Fresh ${idea.strategyVersion} idea · valid until ${localExpiry.hour}:$minute'
            : 'پیشنهاد تازه ${idea.strategyVersion} · معتبر تا ${localExpiry.hour}:$minute';
        await notifications.show(
          id: _stableNotificationId(idea.setupId),
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'quantara_background_setups',
              'Quantara background setups',
              channelDescription:
                  'Fresh paper-trading ideas found by periodic background scans',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: idea.setupId,
        );
      }
      if (changed) {
        final bounded = notified.length <= 250
            ? notified.toList(growable: false)
            : notified.skip(notified.length - 250).toList(growable: false);
        await preferences.setStringList(_backgroundNotifiedKey, bounded);
      }
      return true;
    } on Object {
      return false;
    } finally {
      client.close();
    }
  });
}

int _stableNotificationId(String value) {
  var hash = 17;
  for (final unit in value.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return hash;
}

abstract final class BackgroundOpportunityScanner {
  static Future<void> initialize() =>
      Workmanager().initialize(quantaraBackgroundDispatcher);
}

final class WorkmanagerBackgroundScanGateway
    implements BackgroundScanGateway {
  const WorkmanagerBackgroundScanGateway();

  @override
  Future<void> configure({
    required bool enabled,
    required OwnerAlphaSettings settings,
    required String languageCode,
  }) async {
    if (!enabled) {
      await Workmanager().cancelByUniqueName(_backgroundUniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _backgroundUniqueName,
      _backgroundTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {
        'symbols': settings.symbols,
        'capital': settings.capital,
        'riskPercent': settings.riskPercent,
        'strategy': settings.strategy.name,
        'cadence': settings.cadence.name,
        'languageCode': languageCode,
      },
    );
  }
}
