import 'dart:async';

import '../data/bitunix_private_websocket_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/private_truth_models.dart';
import 'private_order_execution_tracker.dart';
import 'private_truth_reconciler.dart';
import 'private_truth_telemetry.dart';
import 'private_truth_reducer.dart';

typedef PrivateTruthRestFetcher =
    Future<AutoTradeAccountSnapshot> Function(
      BitunixApiCredentials credentials,
    );
typedef PrivateTruthClock = DateTime Function();

final class PrivateTruthRefreshResult {
  const PrivateTruthRefreshResult({
    required this.attempted,
    required this.joinedInFlight,
    required this.freshForEntry,
    required this.reconciliationCycleId,
    required this.completedAtUtc,
    required this.resultCode,
  });

  final bool attempted;
  final bool joinedInFlight;
  final bool freshForEntry;
  final int reconciliationCycleId;
  final DateTime? completedAtUtc;
  final String resultCode;
}

abstract final class PrivateTruthFillMatchPolicy {
  static String? _expectedPositionSide(String orderSide) {
    return switch (orderSide.trim().toUpperCase()) {
      'BUY' => 'LONG',
      'SELL' => 'SHORT',
      _ => null,
    };
  }

  static PrivateTruthFillConfirmation? match({
    required PrivateTruthProjection projection,
    required String orderId,
    required String clientId,
    required String symbol,
  }) {
    final normalizedOrderId = orderId.trim();
    final normalizedClientId = clientId.trim();
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty ||
        (normalizedOrderId.isEmpty && normalizedClientId.isEmpty)) {
      return null;
    }

    final filledOrders = projection.orders.values
        .where(
          (order) =>
              order.symbol.toUpperCase() == normalizedSymbol &&
              ((normalizedOrderId.isNotEmpty &&
                      order.orderId.trim() == normalizedOrderId) ||
                  (normalizedClientId.isNotEmpty &&
                      order.clientId.trim() == normalizedClientId)) &&
              order.orderStatus.toUpperCase() == 'FILLED' &&
              order.dealAmount.isFinite &&
              order.dealAmount > 0,
        )
        .toList(growable: false);
    if (filledOrders.length != 1) return null;
    final order = filledOrders.single;
    final expectedPositionSide = _expectedPositionSide(order.side);
    if (expectedPositionSide == null) return null;

    final matchingPositions = projection.positions.values
        .where(
          (item) =>
              !item.closed &&
              item.positionId.trim().isNotEmpty &&
              item.symbol.toUpperCase() == normalizedSymbol &&
              item.side.trim().toUpperCase() == expectedPositionSide &&
              item.quantity.isFinite &&
              item.quantity > 0 &&
              item.quantity + 1e-9 >= order.dealAmount,
        )
        .toList(growable: false);
    if (matchingPositions.length != 1) return null;

    return PrivateTruthFillConfirmation(
      order: order,
      position: matchingPositions.single,
    );
  }
}

final class PrivateTruthCoordinator {
  PrivateTruthCoordinator(
    this._socketClient,
    this._fetchRestSnapshot, {
    PrivateTruthClock? clock,
    this.restVerificationInterval = const Duration(seconds: 60),
    this.maximumRestVerificationAge = const Duration(seconds: 90),
    this.restRequestsPerVerification = 4,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _projection = PrivateTruthProjection.empty(
         (clock ?? (() => DateTime.now().toUtc()))().toUtc(),
       );

  final PrivateTruthStreamClient _socketClient;
  final PrivateTruthRestFetcher _fetchRestSnapshot;
  final PrivateTruthClock _clock;
  final Duration restVerificationInterval;
  final Duration maximumRestVerificationAge;
  final int restRequestsPerVerification;
  final PrivateTruthTelemetryCollector _telemetry =
      PrivateTruthTelemetryCollector();
  final PrivateOrderExecutionTracker _orderExecutionTracker =
      PrivateOrderExecutionTracker();

  final StreamController<PrivateTruthProjection> _projections =
      StreamController<PrivateTruthProjection>.broadcast(sync: true);

  PrivateTruthProjection _projection;
  AutoTradeAccountSnapshot? _latestRestSnapshot;
  BitunixApiCredentials? _credentials;
  StreamSubscription<PrivateTruthEvent>? _eventSubscription;
  StreamSubscription<PrivateWsClientStatus>? _statusSubscription;
  Timer? _verificationTimer;
  bool _running = false;
  bool _socketActive = false;
  Future<void>? _verificationInFlight;
  bool _disposed = false;
  int _verificationGeneration = 0;
  int _lastVerificationCompletedGeneration = 0;
  DateTime? _lastVerificationCompletedAtUtc;
  String _lastVerificationResultCode = 'notRun';

  Stream<PrivateTruthProjection> get projections => _projections.stream;
  PrivateTruthProjection get current => _projection;
  AutoTradeAccountSnapshot? get latestRestSnapshot => _latestRestSnapshot;
  bool get isRunning => _running;
  int get reconciliationCycleId => _lastVerificationCompletedGeneration;
  DateTime? get reconciliationCompletedAtUtc =>
      _lastVerificationCompletedAtUtc;
  String get reconciliationResultCode => _lastVerificationResultCode;

  PrivateOrderExecutionObservation? orderExecutionObservation(String orderId) =>
      _orderExecutionTracker.observationFor(orderId);

  void recordOrderSubmission({
    required String correlationId,
    DateTime? submittedAtUtc,
  }) {
    _orderExecutionTracker.recordSubmission(
      correlationId: correlationId,
      submittedAtUtc: (submittedAtUtc ?? _clock()).toUtc(),
    );
  }

  PrivateTruthTelemetrySnapshot telemetrySnapshot([DateTime? nowUtc]) =>
      _telemetry.snapshot(
        projection: _projection,
        droppedOrMalformedEvents: _socketClient.droppedOrMalformedEvents,
        nowUtc: (nowUtc ?? _clock()).toUtc(),
      );

  void recordSupervisorPublish(DateTime publishedAtUtc) {
    _telemetry.recordSupervisorPublish(
      projectionUpdatedAtUtc: _projection.updatedAtUtc,
      publishedAtUtc: publishedAtUtc,
    );
  }

  void recordRestRequests(int count, [DateTime? atUtc]) {
    _telemetry.recordRestRequests(count, (atUtc ?? _clock()).toUtc());
  }

  bool get canAdmitNewEntries {
    if (!_running || !_socketActive || !_projection.canAdmitNewEntries) {
      return false;
    }
    final verifiedAt = _projection.restVerifiedAtUtc;
    if (verifiedAt == null) return false;
    final age = _clock().toUtc().difference(verifiedAt);
    return !age.isNegative && age <= maximumRestVerificationAge;
  }

  bool get reduceOnlyManagementAvailable =>
      _projection.reduceOnlyManagementAvailable;

  Future<void> start(BitunixApiCredentials credentials) async {
    if (_disposed) throw StateError('Private truth coordinator is disposed.');
    if (_running) return;
    _orderExecutionTracker.clear();
    _credentials = credentials;
    _running = true;
    _eventSubscription = _socketClient.events.listen(_onEvent);
    _statusSubscription = _socketClient.statuses.listen(_onSocketStatus);
    _setProjection(
      PrivateTruthReducer.markConnecting(
        current: _projection,
        nowUtc: _clock().toUtc(),
      ),
    );
    _verificationTimer = Timer.periodic(restVerificationInterval, (_) {
      if (_running && _socketActive) unawaited(_verifyRest());
    });
    await _socketClient.start(credentials);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _socketActive = false;
    _verificationGeneration++;
    _verificationTimer?.cancel();
    _verificationTimer = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    await _socketClient.stop();
    _orderExecutionTracker.clear();
    _setProjection(
      PrivateTruthReducer.markStale(
        current: _projection,
        nowUtc: _clock().toUtc(),
        reason: PrivateTruthLagReason.disconnected,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _socketClient.dispose();
    await _projections.close();
  }

  void _onEvent(PrivateTruthEvent event) {
    if (!_running) return;
    _telemetry.recordEvent(event);
    final current = _projection;
    final next = PrivateTruthReducer.apply(current: current, event: event);
    if (next.metrics.acceptedEvents > current.metrics.acceptedEvents) {
      _orderExecutionTracker.recordAccepted(event);
    }
    _setProjection(next);
  }

  void _onSocketStatus(PrivateWsClientStatus status) {
    if (!_running) return;
    switch (status.state) {
      case PrivateWsClientState.active:
        _socketActive = true;
        unawaited(_verifyRest());
      case PrivateWsClientState.reconnecting:
        _socketActive = false;
        _telemetry.recordReconnect(status.atUtc);
        _verificationGeneration++;
        _setProjection(
          PrivateTruthReducer.markReconnect(
            current: _projection,
            nowUtc: status.atUtc,
          ),
        );
      case PrivateWsClientState.connecting:
      case PrivateWsClientState.authenticating:
      case PrivateWsClientState.subscribing:
        _socketActive = false;
      case PrivateWsClientState.stopped:
        _socketActive = false;
        if (_running) {
          _setProjection(
            PrivateTruthReducer.markStale(
              current: _projection,
              nowUtc: status.atUtc,
              reason: PrivateTruthLagReason.disconnected,
            ),
          );
        }
    }
  }

  Future<PrivateTruthRefreshResult> refreshForEntryAdmission() async {
    final wasInFlight = _verificationInFlight != null;
    final generationBefore = _verificationGeneration;
    if (!_running) {
      return PrivateTruthRefreshResult(
        attempted: false,
        joinedInFlight: false,
        freshForEntry: false,
        reconciliationCycleId: _lastVerificationCompletedGeneration,
        completedAtUtc: _lastVerificationCompletedAtUtc,
        resultCode: 'notRunning',
      );
    }
    if (!_socketActive) {
      return PrivateTruthRefreshResult(
        attempted: false,
        joinedInFlight: false,
        freshForEntry: false,
        reconciliationCycleId: _lastVerificationCompletedGeneration,
        completedAtUtc: _lastVerificationCompletedAtUtc,
        resultCode: 'socketInactive',
      );
    }
    await _verifyRest();
    return PrivateTruthRefreshResult(
      attempted: wasInFlight || _verificationGeneration > generationBefore,
      joinedInFlight: wasInFlight,
      freshForEntry: canAdmitNewEntries,
      reconciliationCycleId: _lastVerificationCompletedGeneration,
      completedAtUtc: _lastVerificationCompletedAtUtc,
      resultCode: _lastVerificationResultCode,
    );
  }

  Future<PrivateTruthFillConfirmation?> waitForFullFill({
    required String orderId,
    required String clientId,
    required String symbol,
    Duration timeout = const Duration(milliseconds: 3500),
  }) async {
    PrivateTruthFillConfirmation? match(PrivateTruthProjection projection) =>
        PrivateTruthFillMatchPolicy.match(
          projection: projection,
          orderId: orderId,
          clientId: clientId,
          symbol: symbol,
        );

    final immediate = match(_projection);
    if (immediate != null) return immediate;
    try {
      return await projections
          .map(match)
          .where((item) => item != null)
          .cast<PrivateTruthFillConfirmation>()
          .first
          .timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  Future<void> _verifyRest() async {
    if (!_running || !_socketActive) return;
    final existing = _verificationInFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final credentials = _credentials;
    if (credentials == null) return;
    final completer = Completer<void>();
    final inFlight = completer.future;
    _verificationInFlight = inFlight;
    try {
      await _performRestVerification(credentials);
    } finally {
      if (!completer.isCompleted) completer.complete();
      if (identical(_verificationInFlight, inFlight)) {
        _verificationInFlight = null;
      }
    }
  }

  Future<void> _performRestVerification(
    BitunixApiCredentials credentials,
  ) async {
    final generation = ++_verificationGeneration;
    recordRestRequests(restRequestsPerVerification);
    try {
      final snapshot = await _fetchRestSnapshot(credentials);
      if (!_running ||
          !_socketActive ||
          generation != _verificationGeneration) {
        return;
      }
      final completedAt = _clock().toUtc();
      _latestRestSnapshot = snapshot;
      _lastVerificationCompletedGeneration = generation;
      _lastVerificationCompletedAtUtc = completedAt;
      _lastVerificationResultCode = 'fresh';
      _telemetry.recordReconciled(completedAt);
      _setProjection(
        PrivateTruthReconciler.reconcileRestSnapshot(
          current: _projection,
          snapshot: snapshot,
        ),
      );
    } on Object {
      if (!_running || generation != _verificationGeneration) return;
      final completedAt = _clock().toUtc();
      _lastVerificationCompletedGeneration = generation;
      _lastVerificationCompletedAtUtc = completedAt;
      _lastVerificationResultCode = 'failed';
      _setProjection(
        PrivateTruthReducer.markStale(
          current: _projection,
          nowUtc: completedAt,
          reason: PrivateTruthLagReason.restVerificationStale,
        ),
      );
    }
  }

  void _setProjection(PrivateTruthProjection next) {
    _projection = next;
    _telemetry.recordEntryGate(
      canAdmit: canAdmitNewEntries,
      atUtc: _clock().toUtc(),
    );
    if (!_projections.isClosed) _projections.add(next);
  }
}
