import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../trading_journal/application/manual_trade_journal_observer.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../data/manual_trade_execution_store.dart';
import '../data/secure_auto_trade_credentials_store.dart';
import '../domain/auto_trade_models.dart';
import '../domain/full_position_stop_policy.dart';
import '../domain/manual_trade_execution.dart';
import '../domain/local_live_trade_models.dart';
import '../domain/private_account_reconciliation.dart';
import 'auto_trade_controller.dart';

final class ManualTradeExecutionException implements Exception {
  const ManualTradeExecutionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ManualTradePreparation {
  const ManualTradePreparation({
    required this.setup,
    required this.account,
    required this.rules,
    required this.markPrice,
    required this.systemProposal,
    required this.plan,
  });

  final SignalJournalEntry setup;
  final AutoTradeAccountSnapshot account;
  final ManualTradeInstrumentRules rules;
  final double markPrice;
  final ManualTradePlan systemProposal;
  final ManualTradePlan plan;

  ManualTradePreparation copyWith({required ManualTradePlan plan}) =>
      ManualTradePreparation(
        setup: setup,
        account: account,
        rules: rules,
        markPrice: markPrice,
        systemProposal: systemProposal,
        plan: plan,
      );
}

final class ManualTradeExecutionReceipt {
  const ManualTradeExecutionReceipt({
    required this.setupId,
    required this.symbol,
    required this.positionId,
    required this.entryOrderId,
    required this.stopOrderId,
    required this.targetOrderIds,
    required this.clientId,
    required this.openedAtUtc,
    required this.plan,
    this.warning,
  });

  final String setupId;
  final String symbol;
  final String positionId;
  final String entryOrderId;
  final String stopOrderId;
  final List<String> targetOrderIds;
  final String clientId;
  final DateTime openedAtUtc;
  final ManualTradePlan plan;
  final String? warning;
}

abstract interface class ManualTradeAccountGateway {
  AutoTradeAccountSnapshot? get snapshot;
  bool get canStartNewEntry;

  Future<bool> reconcile({
    required PrivateAccountRefreshReason reason,
    bool force = false,
  });
}

final class AutoTradeManualTradeAccountGateway
    implements ManualTradeAccountGateway {
  const AutoTradeManualTradeAccountGateway(this.controller);

  final AutoTradeController controller;

  @override
  AutoTradeAccountSnapshot? get snapshot => controller.snapshot;

  @override
  bool get canStartNewEntry => controller.canStartNewEntry;

  @override
  Future<bool> reconcile({
    required PrivateAccountRefreshReason reason,
    bool force = false,
  }) => controller.reconcile(reason: reason, force: force);
}

abstract interface class ManualTradeExchangeGateway {
  Future<double> fetchMarkPrice(String symbol);
  Future<BitunixInstrumentRules> fetchInstrumentRules(String symbol);
  Future<AutoTradeAccountSnapshot> fetchCurrentAccountSnapshot(
    BitunixApiCredentials credentials,
  );
  Future<void> ensureIsolatedMargin({
    required String symbol,
    required BitunixApiCredentials credentials,
  });
  Future<void> changeLeverage({
    required String symbol,
    required int leverage,
    required BitunixApiCredentials credentials,
  });
  Future<BitunixPlacedOrder> placeMarketEntry({
    required String symbol,
    required double quantity,
    required bool long,
    required String clientId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  });
  Future<List<BitunixPendingProtection>> fetchPendingProtection(
    BitunixApiCredentials credentials, {
    String? symbol,
    String? positionId,
  });
  Future<String> placePositionStop({
    required String symbol,
    required String positionId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  });
  Future<String> placePartialTakeProfit({
    required String symbol,
    required String positionId,
    required double triggerPrice,
    required double quantity,
    required BitunixApiCredentials credentials,
  });
  Future<BitunixOrderDetail> fetchOrderDetail({
    required String orderId,
    required BitunixApiCredentials credentials,
  });
  Future<List<BitunixLivePosition>> fetchPositions(
    BitunixApiCredentials credentials, {
    String? symbol,
  });
  Future<void> cancelEntryOrder({
    required String symbol,
    required String orderId,
    required String clientId,
    required BitunixApiCredentials credentials,
  });
  Future<BitunixPlacedOrder> closePositionReduceOnly({
    required BitunixLivePosition position,
    required String clientId,
    required BitunixApiCredentials credentials,
  });
}

final class BitunixManualTradeExchangeGateway
    implements ManualTradeExchangeGateway {
  const BitunixManualTradeExchangeGateway(this.client);

  final BitunixLocalLiveApiClient client;

  @override
  Future<double> fetchMarkPrice(String symbol) {
    return client.fetchMarkPrice(symbol);
  }

  @override
  Future<BitunixInstrumentRules> fetchInstrumentRules(String symbol) {
    return client.fetchInstrumentRules(symbol);
  }

  @override
  Future<AutoTradeAccountSnapshot> fetchCurrentAccountSnapshot(
    BitunixApiCredentials credentials,
  ) {
    return client.fetchCurrentAccountSnapshot(credentials);
  }

  @override
  Future<void> ensureIsolatedMargin({
    required String symbol,
    required BitunixApiCredentials credentials,
  }) {
    return client.ensureIsolatedMargin(
      symbol: symbol,
      credentials: credentials,
    );
  }

  @override
  Future<void> changeLeverage({
    required String symbol,
    required int leverage,
    required BitunixApiCredentials credentials,
  }) {
    return client.changeLeverage(
      symbol: symbol,
      leverage: leverage,
      credentials: credentials,
    );
  }

  @override
  Future<BitunixPlacedOrder> placeMarketEntry({
    required String symbol,
    required double quantity,
    required bool long,
    required String clientId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) {
    return client.placeMarketEntry(
      symbol: symbol,
      quantity: quantity,
      long: long,
      clientId: clientId,
      stopLoss: stopLoss,
      credentials: credentials,
    );
  }

  @override
  Future<List<BitunixPendingProtection>> fetchPendingProtection(
    BitunixApiCredentials credentials, {
    String? symbol,
    String? positionId,
  }) {
    return client.fetchPendingProtection(
      credentials,
      symbol: symbol,
      positionId: positionId,
    );
  }

  @override
  Future<String> placePositionStop({
    required String symbol,
    required String positionId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) {
    return client.placePositionStop(
      symbol: symbol,
      positionId: positionId,
      stopLoss: stopLoss,
      credentials: credentials,
    );
  }

  @override
  Future<String> placePartialTakeProfit({
    required String symbol,
    required String positionId,
    required double triggerPrice,
    required double quantity,
    required BitunixApiCredentials credentials,
  }) {
    return client.placePartialTakeProfit(
      symbol: symbol,
      positionId: positionId,
      triggerPrice: triggerPrice,
      quantity: quantity,
      credentials: credentials,
    );
  }

  @override
  Future<BitunixOrderDetail> fetchOrderDetail({
    required String orderId,
    required BitunixApiCredentials credentials,
  }) {
    return client.fetchOrderDetail(
      orderId: orderId,
      credentials: credentials,
    );
  }

  @override
  Future<List<BitunixLivePosition>> fetchPositions(
    BitunixApiCredentials credentials, {
    String? symbol,
  }) {
    return client.fetchPositions(credentials, symbol: symbol);
  }

  @override
  Future<void> cancelEntryOrder({
    required String symbol,
    required String orderId,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) {
    return client.cancelEntryOrder(
      symbol: symbol,
      orderId: orderId,
      clientId: clientId,
      credentials: credentials,
    );
  }

  @override
  Future<BitunixPlacedOrder> closePositionReduceOnly({
    required BitunixLivePosition position,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) {
    return client.closePositionReduceOnly(
      position: position,
      clientId: clientId,
      credentials: credentials,
    );
  }
}

final class ManualTradeExecutionController extends ChangeNotifier {
  factory ManualTradeExecutionController({
    required AutoTradeController accountController,
    required BitunixLocalLiveApiClient exchange,
    AutoTradeCredentialsStore credentialsStore =
        const SecureAutoTradeCredentialsStore(),
    ManualTradeExecutionStore? executionStore,
    ManualTradeJournalObserver? journalObserver,
    DateTime Function()? utcNow,
    Duration exchangePollDelay = const Duration(milliseconds: 500),
  }) {
    return ManualTradeExecutionController.withGateways(
      accountGateway: AutoTradeManualTradeAccountGateway(accountController),
      exchangeGateway: BitunixManualTradeExchangeGateway(exchange),
      credentialsStore: credentialsStore,
      executionStore: executionStore,
      journalObserver: journalObserver,
      utcNow: utcNow,
      exchangePollDelay: exchangePollDelay,
    );
  }

  factory ManualTradeExecutionController.withGateways({
    required ManualTradeAccountGateway accountGateway,
    required ManualTradeExchangeGateway exchangeGateway,
    AutoTradeCredentialsStore credentialsStore =
        const SecureAutoTradeCredentialsStore(),
    ManualTradeExecutionStore? executionStore,
    ManualTradeJournalObserver? journalObserver,
    DateTime Function()? utcNow,
    Duration exchangePollDelay = const Duration(milliseconds: 500),
  }) {
    return ManualTradeExecutionController._internal(
      accountGateway: accountGateway,
      exchangeGateway: exchangeGateway,
      credentialsStore: credentialsStore,
      executionStore:
          executionStore ?? SharedPreferencesManualTradeExecutionStore(),
      journalObserver: journalObserver ?? ManualTradeJournalObserver(),
      utcNow: utcNow ?? DateTime.now,
      exchangePollDelay: exchangePollDelay,
    );
  }

  ManualTradeExecutionController._internal({
    required this.accountGateway,
    required this.exchangeGateway,
    required this.credentialsStore,
    required this._executionStore,
    required this._journalObserver,
    required this._utcNow,
    required this.exchangePollDelay,
  });

  final ManualTradeAccountGateway accountGateway;
  final ManualTradeExchangeGateway exchangeGateway;
  final AutoTradeCredentialsStore credentialsStore;
  final ManualTradeExecutionStore _executionStore;
  final ManualTradeJournalObserver _journalObserver;
  final DateTime Function() _utcNow;
  final Duration exchangePollDelay;

  ManualTradePreparation? _preparation;
  bool _busy = false;
  String? _error;
  ManualTradeExecutionReceipt? _lastReceipt;

  ManualTradePreparation? get preparation => _preparation;
  bool get isBusy => _busy;
  String? get error => _error;
  ManualTradeExecutionReceipt? get lastReceipt => _lastReceipt;

  Future<ManualTradePreparation?> prepare(SignalJournalEntry setup) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    _lastReceipt = null;
    notifyListeners();
    try {
      final credentials = await credentialsStore.load();
      if (credentials == null) {
        throw const ManualTradeExecutionException(
          'Connect and validate the Bitunix account before opening a setup.',
        );
      }
      final reconciled = await accountGateway.reconcile(
        reason: PrivateAccountRefreshReason.startPreflight,
        force: true,
      );
      final account = accountGateway.snapshot;
      if (!reconciled ||
          account == null ||
          !accountGateway.canStartNewEntry) {
        throw const ManualTradeExecutionException(
          'A fresh, coherent and fully protected Bitunix account state is required before a new manual entry.',
        );
      }
      await _resolvePreviousIntentIfSafe(
        setup: setup,
        credentials: credentials,
      );
      final values = await Future.wait<Object>([
        exchangeGateway.fetchMarkPrice(setup.symbol),
        exchangeGateway.fetchInstrumentRules(setup.symbol),
      ]);
      final markPrice = values[0] as double;
      final exchangeRules = values[1] as BitunixInstrumentRules;
      final rules = _rules(exchangeRules);
      final availableTargets = math.min(3, setup.targets.length).toInt();
      if (availableTargets < 1) {
        throw const ManualTradeExecutionException(
          'This setup does not have a valid take-profit target.',
        );
      }
      final plan = ManualTradeSizingPolicy.propose(
        setup: setup,
        account: account,
        rules: rules,
        markPrice: markPrice,
        nowUtc: _utcNow().toUtc(),
        targetCount: availableTargets,
      );
      _preparation = ManualTradePreparation(
        setup: setup,
        account: account,
        rules: rules,
        markPrice: markPrice,
        systemProposal: plan,
        plan: plan,
      );
      if (!plan.allowed) _error = plan.explanation;
      return _preparation;
    } on ManualTradeExecutionException catch (error) {
      _error = error.message;
      _preparation = null;
      return null;
    } on LocalLiveTradeSafeException catch (error) {
      _error = error.message;
      _preparation = null;
      return null;
    } on Object {
      _error = 'Manual trade preflight could not be completed safely.';
      _preparation = null;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void recalculate({
    required double margin,
    required int leverage,
    required int targetCount,
  }) {
    final current = _preparation;
    if (current == null || _busy) return;
    final plan = ManualTradeSizingPolicy.recalculate(
      setup: current.setup,
      account: current.account,
      rules: current.rules,
      markPrice: current.markPrice,
      nowUtc: _utcNow().toUtc(),
      margin: margin,
      leverage: leverage,
      targetCount: targetCount,
    );
    _preparation = current.copyWith(plan: plan);
    _error = plan.allowed ? null : plan.explanation;
    notifyListeners();
  }

  Future<ManualTradeExecutionReceipt?> confirmAndExecute() async {
    final prepared = _preparation;
    if (_busy || prepared == null || !prepared.plan.allowed) return null;
    _busy = true;
    _error = null;
    _lastReceipt = null;
    notifyListeners();

    ManualTradeExecutionRecord? intent;
    BitunixLivePosition? openedPosition;
    BitunixApiCredentials? activeCredentials;
    try {
      final credentials = await credentialsStore.load();
      if (credentials == null) {
        throw const ManualTradeExecutionException(
          'Bitunix credentials are unavailable.',
        );
      }
      activeCredentials = credentials;
      final reconciled = await accountGateway.reconcile(
        reason: PrivateAccountRefreshReason.startPreflight,
        force: true,
      );
      final account = accountGateway.snapshot;
      if (!reconciled ||
          account == null ||
          !accountGateway.canStartNewEntry) {
        throw const ManualTradeExecutionException(
          'Account truth changed before confirmation; the trade was not submitted.',
        );
      }

      final existing = await _executionStore.load(prepared.setup.setupId);
      if (existing?.blocksDuplicateSubmission == true) {
        throw const ManualTradeExecutionException(
          'This setup already has a submitted, ambiguous, or protected manual execution. Duplicate submission is blocked.',
        );
      }

      final values = await Future.wait<Object>([
        exchangeGateway.fetchMarkPrice(prepared.setup.symbol),
        exchangeGateway.fetchInstrumentRules(prepared.setup.symbol),
      ]);
      final currentMark = values[0] as double;
      final rules = _rules(values[1] as BitunixInstrumentRules);
      final plan = ManualTradeSizingPolicy.recalculate(
        setup: prepared.setup,
        account: account,
        rules: rules,
        markPrice: currentMark,
        nowUtc: _utcNow().toUtc(),
        margin: prepared.plan.margin,
        leverage: prepared.plan.leverage,
        targetCount: prepared.plan.targetCount,
      );
      _preparation = ManualTradePreparation(
        setup: prepared.setup,
        account: account,
        rules: rules,
        markPrice: currentMark,
        systemProposal: prepared.systemProposal,
        plan: plan,
      );
      if (!plan.allowed) {
        throw ManualTradeExecutionException(
          'Final preflight rejected the trade: ${plan.explanation}',
        );
      }

      final clientId = _clientId(prepared.setup);
      intent = ManualTradeExecutionRecord(
        setupId: prepared.setup.setupId,
        symbol: prepared.setup.symbol,
        clientId: clientId,
        state: ManualTradeExecutionState.submitting,
        updatedAtUtc: _utcNow().toUtc(),
        margin: plan.margin,
        leverage: plan.leverage,
        targetCount: plan.targetCount,
        systemMargin: prepared.systemProposal.margin,
        systemLeverage: prepared.systemProposal.leverage,
        systemTargetCount: prepared.systemProposal.targetCount,
        message: 'Persisted before the first exchange mutation.',
      );
      await _executionStore.save(intent);

      await exchangeGateway.ensureIsolatedMargin(
        symbol: prepared.setup.symbol,
        credentials: credentials,
      );
      await exchangeGateway.changeLeverage(
        symbol: prepared.setup.symbol,
        leverage: plan.leverage,
        credentials: credentials,
      );

      BitunixPlacedOrder placed;
      try {
        placed = await exchangeGateway.placeMarketEntry(
          symbol: prepared.setup.symbol,
          quantity: plan.quantity,
          long: prepared.setup.direction == TradeDirection.long,
          clientId: clientId,
          stopLoss: plan.stopLoss,
          credentials: credentials,
        );
      } on Object catch (error) {
        await _executionStore.save(
          intent.copyWith(
            state: ManualTradeExecutionState.ambiguous,
            updatedAtUtc: _utcNow().toUtc(),
            message:
                'Entry transport failed after mutation start: ${error.runtimeType}.',
          ),
        );
        throw const ManualTradeExecutionException(
          'The entry request became ambiguous. Quantara will not retry it automatically or risk a duplicate position.',
        );
      }

      intent = intent.copyWith(
        entryOrderId: placed.orderId,
        updatedAtUtc: _utcNow().toUtc(),
        message: 'Bitunix acknowledged the entry order identity.',
      );
      await _executionStore.save(intent);

      final fill = await _waitForFullFill(
        credentials: credentials,
        order: placed,
        setup: prepared.setup,
      );
      if (fill == null) {
        await _failClosedIncompleteEntry(
          credentials: credentials,
          order: placed,
          setup: prepared.setup,
          intent: intent,
        );
        throw const ManualTradeExecutionException(
          'Entry was not confirmed as a full fill; fail-closed cleanup was applied.',
        );
      }
      final detail = fill.$1;
      final position = fill.$2;
      openedPosition = position;
      final quantityTolerance = math
          .pow(10, -rules.quantityPrecision)
          .toDouble();
      if ((detail.filledQuantity - plan.quantity).abs() > quantityTolerance ||
          (position.quantity - plan.quantity).abs() > quantityTolerance) {
        await _closeUnprotected(
          credentials: credentials,
          position: position,
          clientId: '$clientId-fill-mismatch',
          intent: intent,
          message:
              'Exchange fill quantity did not match the explicitly confirmed quantity.',
        );
        throw const ManualTradeExecutionException(
          'Exchange fill quantity differed from the confirmed plan; the position was closed fail-closed.',
        );
      }

      final priceTolerance = math.pow(10, -rules.pricePrecision).toDouble() / 2;
      var protections = await exchangeGateway.fetchPendingProtection(
        credentials,
        symbol: prepared.setup.symbol,
        positionId: position.positionId,
      );
      String? stopOrderId = _confirmedStopOrderId(
        protections: protections,
        positionId: position.positionId,
        quantity: plan.quantity,
        expectedStop: plan.stopLoss,
        quantityTolerance: quantityTolerance,
        priceTolerance: priceTolerance,
      );
      stopOrderId ??= await exchangeGateway.placePositionStop(
        symbol: prepared.setup.symbol,
        positionId: position.positionId,
        stopLoss: plan.stopLoss,
        credentials: credentials,
      );
      protections = await exchangeGateway.fetchPendingProtection(
        credentials,
        symbol: prepared.setup.symbol,
        positionId: position.positionId,
      );
      if (_confirmedStopOrderId(
            protections: protections,
            positionId: position.positionId,
            quantity: plan.quantity,
            expectedStop: plan.stopLoss,
            quantityTolerance: quantityTolerance,
            priceTolerance: priceTolerance,
          ) ==
          null) {
        await _closeUnprotected(
          credentials: credentials,
          position: position,
          clientId: '$clientId-stop-close',
          intent: intent,
          message: 'A full exchange-confirmed stop loss could not be proven.',
        );
        throw const ManualTradeExecutionException(
          'Stop loss could not be verified on Bitunix; the position was closed fail-closed.',
        );
      }

      final targetOrderIds = <String>[];
      try {
        for (var index = 0; index < plan.targetCount; index++) {
          targetOrderIds.add(
            await exchangeGateway.placePartialTakeProfit(
              symbol: prepared.setup.symbol,
              positionId: position.positionId,
              triggerPrice: plan.targets[index],
              quantity: plan.targetQuantities[index],
              credentials: credentials,
            ),
          );
        }
      } on Object catch (error) {
        await _closeUnprotected(
          credentials: credentials,
          position: position,
          clientId: '$clientId-tp-close',
          intent: intent,
          message: 'TP placement failed: ${error.runtimeType}.',
        );
        throw const ManualTradeExecutionException(
          'The selected TP ladder could not be created completely; the position was closed fail-closed.',
        );
      }

      var ladderConfirmed = false;
      for (var attempt = 0; attempt < 6; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(exchangePollDelay);
        }
        protections = await exchangeGateway.fetchPendingProtection(
          credentials,
          symbol: prepared.setup.symbol,
          positionId: position.positionId,
        );
        ladderConfirmed = _protectionPlanConfirmed(
          protections: protections,
          positionId: position.positionId,
          plan: plan,
          stopOrderId: stopOrderId,
          targetOrderIds: targetOrderIds,
          quantityTolerance: quantityTolerance,
          priceTolerance: priceTolerance,
        );
        if (ladderConfirmed) break;
      }
      if (!ladderConfirmed) {
        await _closeUnprotected(
          credentials: credentials,
          position: position,
          clientId: '$clientId-incomplete-protection-close',
          intent: intent,
          message: 'The complete exchange SL/TP ladder was not verified.',
        );
        throw const ManualTradeExecutionException(
          'The complete SL/TP ladder was not verified; the position was closed fail-closed.',
        );
      }

      final protectedRecord = intent.copyWith(
        state: ManualTradeExecutionState.protected,
        updatedAtUtc: _utcNow().toUtc(),
        positionId: position.positionId,
        stopOrderId: stopOrderId,
        targetOrderIds: targetOrderIds,
        message:
            'Entry, full stop and explicitly selected target ladder are exchange-confirmed.',
      );
      await _executionStore.save(protectedRecord);

      final openedAt = position.openedAt?.toUtc() ?? _utcNow().toUtc();
      String? journalWarning;
      try {
        await _journalObserver.recordProtectedTrade(
          setup: prepared.setup,
          systemProposal: prepared.systemProposal,
          plan: plan,
          account: account,
          positionId: position.positionId,
          entryOrderId: placed.orderId,
          clientId: clientId,
          actualEntryPrice: position.averageOpenPrice > 0
              ? position.averageOpenPrice
              : plan.entryPrice,
          stopOrderId: stopOrderId,
          targetOrderIds: targetOrderIds,
          openedAtUtc: openedAt,
        );
      } on Object {
        journalWarning =
            'The position is protected on Bitunix, but local journal persistence needs reconciliation.';
      }

      await accountGateway.reconcile(
        reason: PrivateAccountRefreshReason.manual,
        force: true,
      );
      final receipt = ManualTradeExecutionReceipt(
        setupId: prepared.setup.setupId,
        symbol: prepared.setup.symbol,
        positionId: position.positionId,
        entryOrderId: placed.orderId,
        stopOrderId: stopOrderId,
        targetOrderIds: List.unmodifiable(targetOrderIds),
        clientId: clientId,
        openedAtUtc: openedAt,
        plan: plan,
        warning: journalWarning,
      );
      _lastReceipt = receipt;
      _preparation = _preparation?.copyWith(plan: plan);
      return receipt;
    } on ManualTradeExecutionException catch (error) {
      _error = error.message;
      return null;
    } on LocalLiveTradeSafeException catch (error) {
      await _cleanupUnexpectedExposureIfNeeded(
        credentials: activeCredentials,
        position: openedPosition,
        intent: intent,
        message:
            'Unexpected exchange-safe failure after exposure existed: ${error.message}',
      );
      _error = error.message;
      return null;
    } on Object catch (error) {
      await _cleanupUnexpectedExposureIfNeeded(
        credentials: activeCredentials,
        position: openedPosition,
        intent: intent,
        message:
            'Unexpected execution failure after exposure existed: ${error.runtimeType}.',
      );
      _error =
          'Manual trade execution stopped safely because an unexpected error occurred.';
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _resolvePreviousIntentIfSafe({
    required SignalJournalEntry setup,
    required BitunixApiCredentials credentials,
  }) async {
    final record = await _executionStore.load(setup.setupId);
    if (record == null || !record.blocksDuplicateSubmission) return;
    if (record.state == ManualTradeExecutionState.protected) {
      throw const ManualTradeExecutionException(
        'This setup already opened a protected manual position.',
      );
    }

    final snapshot = await exchangeGateway.fetchCurrentAccountSnapshot(
      credentials,
    );
    final sameSymbolPosition = snapshot.positions.any(
      (position) =>
          position.quantity > 0 &&
          position.symbol.trim().toUpperCase() ==
              setup.symbol.trim().toUpperCase(),
    );
    final sameClientOrder = snapshot.orders.any(
      (order) => order.clientId.trim() == record.clientId.trim(),
    );
    if (sameSymbolPosition || sameClientOrder) {
      throw const ManualTradeExecutionException(
        'A previous manual attempt still has exchange exposure or an order identity; duplicate submission remains blocked.',
      );
    }
    throw const ManualTradeExecutionException(
      'A previous entry attempt is ambiguous. Current flat account state cannot prove that the order never executed, so this setup will not be submitted again automatically.',
    );
  }

  Future<(BitunixOrderDetail, BitunixLivePosition)?> _waitForFullFill({
    required BitunixApiCredentials credentials,
    required BitunixPlacedOrder order,
    required SignalJournalEntry setup,
  }) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(exchangePollDelay);
      }
      final values = await Future.wait<Object>([
        exchangeGateway.fetchOrderDetail(
          orderId: order.orderId,
          credentials: credentials,
        ),
        exchangeGateway.fetchPositions(credentials, symbol: setup.symbol),
      ]);
      final detail = values[0] as BitunixOrderDetail;
      final position = _matchingPosition(
        values[1] as List<BitunixLivePosition>,
        setup,
      );
      if (detail.fullyFilled && position != null && position.quantity > 0) {
        return (detail, position);
      }
    }
    return null;
  }

  Future<void> _failClosedIncompleteEntry({
    required BitunixApiCredentials credentials,
    required BitunixPlacedOrder order,
    required SignalJournalEntry setup,
    required ManualTradeExecutionRecord intent,
  }) async {
    try {
      await exchangeGateway.cancelEntryOrder(
        symbol: setup.symbol,
        orderId: order.orderId,
        clientId: order.clientId,
        credentials: credentials,
      );
    } on Object {
      await _markAmbiguous(
        intent,
        'Entry did not fully reconcile and cancellation was not confirmed.',
      );
      return;
    }
    final positions = await exchangeGateway.fetchPositions(
      credentials,
      symbol: setup.symbol,
    );
    final position = _matchingPosition(positions, setup);
    if (position != null && position.quantity > 0) {
      try {
        await exchangeGateway.closePositionReduceOnly(
          position: position,
          clientId: '${order.clientId}-partial-close',
          credentials: credentials,
        );
      } on Object {
        await _markAmbiguous(
          intent,
          'Partial exposure remained after an incomplete entry and close confirmation failed.',
        );
        return;
      }
    }
    await _executionStore.save(
      intent.copyWith(
        state: ManualTradeExecutionState.failedSafe,
        updatedAtUtc: _utcNow().toUtc(),
        message: 'Incomplete entry was cancelled and any exposure was closed.',
      ),
    );
  }

  Future<void> _closeUnprotected({
    required BitunixApiCredentials credentials,
    required BitunixLivePosition position,
    required String clientId,
    required ManualTradeExecutionRecord intent,
    required String message,
  }) async {
    try {
      await exchangeGateway.closePositionReduceOnly(
        position: position,
        clientId: clientId,
        credentials: credentials,
      );
      await _executionStore.save(
        intent.copyWith(
          state: ManualTradeExecutionState.failedSafe,
          updatedAtUtc: _utcNow().toUtc(),
          positionId: position.positionId,
          message: '$message Exposure was confirmed flat by Bitunix.',
        ),
      );
    } on Object {
      await _markAmbiguous(
        intent.copyWith(positionId: position.positionId),
        '$message Reduce-only fail-closed cleanup could not prove the position flat.',
      );
      rethrow;
    }
  }

  Future<void> _cleanupUnexpectedExposureIfNeeded({
    required BitunixApiCredentials? credentials,
    required BitunixLivePosition? position,
    required ManualTradeExecutionRecord? intent,
    required String message,
  }) async {
    if (credentials == null || position == null || intent == null) return;
    final persisted = await _executionStore.load(intent.setupId);
    if (persisted == null ||
        persisted.state != ManualTradeExecutionState.submitting) {
      return;
    }
    try {
      await _closeUnprotected(
        credentials: credentials,
        position: position,
        clientId: '${intent.clientId}-unexpected-close',
        intent: persisted,
        message: message,
      );
    } on Object {
      // _closeUnprotected persists an ambiguous state when flatness cannot be
      // proven. Never retry the entry from this catch path.
    }
  }

  Future<void> _markAmbiguous(
    ManualTradeExecutionRecord record,
    String message,
  ) => _executionStore.save(
    record.copyWith(
      state: ManualTradeExecutionState.ambiguous,
      updatedAtUtc: _utcNow().toUtc(),
      message: message,
    ),
  );

  BitunixLivePosition? _matchingPosition(
    List<BitunixLivePosition> positions,
    SignalJournalEntry setup,
  ) {
    final expected = setup.direction == TradeDirection.long ? 'LONG' : 'SHORT';
    final matching = positions
        .where(
          (position) =>
              position.quantity > 0 &&
              position.symbol.trim().toUpperCase() ==
                  setup.symbol.trim().toUpperCase() &&
              position.side.toUpperCase().contains(expected),
        )
        .toList(growable: false);
    return matching.length == 1 ? matching.single : null;
  }

  String? _confirmedStopOrderId({
    required List<BitunixPendingProtection> protections,
    required String positionId,
    required double quantity,
    required double expectedStop,
    required double quantityTolerance,
    required double priceTolerance,
  }) => protections
      .where(
        (item) => FullPositionStopPolicy.isConfirmed(
          evidencePositionId: item.positionId,
          expectedPositionId: positionId,
          stopLossPrice: item.stopLossPrice,
          stopLossQuantity: item.stopLossQuantity,
          remainingQuantity: quantity,
          quantityTolerance: quantityTolerance,
          expectedStopLossPrice: expectedStop,
          priceTolerance: priceTolerance,
        ),
      )
      .map((item) => item.orderId.trim())
      .where((item) => item.isNotEmpty)
      .firstOrNull;

  bool _protectionPlanConfirmed({
    required List<BitunixPendingProtection> protections,
    required String positionId,
    required ManualTradePlan plan,
    required String stopOrderId,
    required List<String> targetOrderIds,
    required double quantityTolerance,
    required double priceTolerance,
  }) {
    final stop = _confirmedStopOrderId(
      protections: protections,
      positionId: positionId,
      quantity: plan.quantity,
      expectedStop: plan.stopLoss,
      quantityTolerance: quantityTolerance,
      priceTolerance: priceTolerance,
    );
    if (stop == null || stop != stopOrderId.trim()) return false;
    if (targetOrderIds.length != plan.targetCount) return false;

    final comparisonTolerance = quantityTolerance / 2;
    for (var index = 0; index < targetOrderIds.length; index++) {
      final id = targetOrderIds[index].trim();
      final expectedPrice = plan.targets[index];
      final expectedQuantity = plan.targetQuantities[index];
      final confirmed = protections.any(
        (item) =>
            item.positionId.trim() == positionId.trim() &&
            item.orderId.trim() == id &&
            (item.takeProfitPrice - expectedPrice).abs() <= priceTolerance &&
            item.takeProfitQuantity.isFinite &&
            item.takeProfitQuantity > 0 &&
            item.takeProfitQuantity + comparisonTolerance >= expectedQuantity,
      );
      if (!confirmed) return false;
    }
    return true;
  }

  ManualTradeInstrumentRules _rules(BitunixInstrumentRules rules) =>
      ManualTradeInstrumentRules(
        symbol: rules.symbol,
        minimumQuantity: rules.minimumQuantity,
        maximumMarketQuantity: rules.maximumMarketQuantity,
        quantityPrecision: rules.quantityPrecision,
        pricePrecision: rules.pricePrecision,
        minimumLeverage: rules.minimumLeverage,
        maximumLeverage: rules.maximumLeverage,
        open: rules.open,
        apiSupported: rules.apiSupported,
      );

  String _clientId(SignalJournalEntry setup) {
    var hash = 0x811c9dc5;
    final input =
        '${setup.setupId}|${setup.symbol}|${setup.direction.name}|manual';
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'q-manual-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
