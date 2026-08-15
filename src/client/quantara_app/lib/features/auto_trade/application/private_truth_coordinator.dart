import 'dart:async';

import '../data/bitunix_private_websocket_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/private_truth_models.dart';
import 'private_truth_reconciler.dart';
import 'private_truth_reducer.dart';

typedef PrivateTruthRestFetcher =
    Future<AutoTradeAccountSnapshot> Function(
      BitunixApiCredentials credentials,
    );
typedef PrivateTruthClock = DateTime Function();

final class PrivateTruthCoordinator {
  PrivateTruthCoordinator(
    this._socketClient,
    this._fetchRestSnapshot, {
    PrivateTruthClock? clock,
    this.restVerificationInterval = const Duration(seconds: 60),
    this.maximumRestVerificationAge = const Duration(seconds: 90),
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _projection = PrivateTruthProjection.empty(
         (clock ?? (() => DateTime.now().toUtc()))().toUtc(),
       );

  final PrivateTruthStreamClient _socketClient;
  final PrivateTruthRestFetcher _fetchRestSnapshot;
  final PrivateTruthClock _clock;
  final Duration restVerificationInterval;
  final Duration maximumRestVerificationAge;

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
  bool _verifying = false;
  bool _disposed = false;
  int _verificationGeneration = 0;

  Stream<PrivateTruthProjection> get projections => _projections.stream;
  PrivateTruthProjection get current => _projection;
  AutoTradeAccountSnapshot? get latestRestSnapshot => _latestRestSnapshot;
  bool get isRunning => _running;

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
    _setProjection(
      PrivateTruthReducer.apply(current: _projection, event: event),
    );
  }

  void _onSocketStatus(PrivateWsClientStatus status) {
    if (!_running) return;
    switch (status.state) {
      case PrivateWsClientState.active:
        _socketActive = true;
        unawaited(_verifyRest());
      case PrivateWsClientState.reconnecting:
        _socketActive = false;
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

  Future<PrivateTruthFillConfirmation?> waitForFullFill({
    required String orderId,
    required String clientId,
    required String symbol,
    Duration timeout = const Duration(milliseconds: 3500),
  }) async {
    PrivateTruthFillConfirmation? match(PrivateTruthProjection projection) {
      final normalizedOrderId = orderId.trim();
      final normalizedClientId = clientId.trim();
      final normalizedSymbol = symbol.trim().toUpperCase();
      final matchingOrders = projection.orders.values.where(
        (order) =>
            order.symbol.toUpperCase() == normalizedSymbol &&
            ((normalizedOrderId.isNotEmpty &&
                    order.orderId.trim() == normalizedOrderId) ||
                (normalizedClientId.isNotEmpty &&
                    order.clientId.trim() == normalizedClientId)),
      );
      final order = matchingOrders
          .where((item) => item.orderStatus.toUpperCase() == 'FILLED')
          .firstOrNull;
      if (order == null || order.dealAmount <= 0) return null;
      final position = projection.positions.values
          .where(
            (item) =>
                !item.closed &&
                item.symbol.toUpperCase() == normalizedSymbol &&
                item.quantity + 1e-9 >= order.dealAmount,
          )
          .firstOrNull;
      if (position == null) return null;
      return PrivateTruthFillConfirmation(order: order, position: position);
    }

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
    if (!_running || !_socketActive || _verifying) return;
    final credentials = _credentials;
    if (credentials == null) return;
    _verifying = true;
    final generation = ++_verificationGeneration;
    try {
      final snapshot = await _fetchRestSnapshot(credentials);
      if (!_running ||
          !_socketActive ||
          generation != _verificationGeneration) {
        return;
      }
      _latestRestSnapshot = snapshot;
      _setProjection(
        PrivateTruthReconciler.reconcileRestSnapshot(
          current: _projection,
          snapshot: snapshot,
        ),
      );
    } on Object {
      if (!_running || generation != _verificationGeneration) return;
      _setProjection(
        PrivateTruthReducer.markStale(
          current: _projection,
          nowUtc: _clock().toUtc(),
          reason: PrivateTruthLagReason.restVerificationStale,
        ),
      );
    } finally {
      if (generation == _verificationGeneration) _verifying = false;
    }
  }

  void _setProjection(PrivateTruthProjection next) {
    _projection = next;
    if (!_projections.isClosed) _projections.add(next);
  }
}
