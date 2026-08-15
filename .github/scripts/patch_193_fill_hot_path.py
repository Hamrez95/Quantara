from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'missing patch target in {path}: {old[:120]!r}')
    path.write_text(text.replace(old, new, 1))


client = ROOT / 'lib/features/auto_trade/data/bitunix_private_websocket_client.dart'
replace_once(
    client,
    'final class BitunixPrivateWebSocketClient {\n',
    '''abstract interface class PrivateTruthStreamClient {\n  Stream<PrivateTruthEvent> get events;\n  Stream<PrivateWsClientStatus> get statuses;\n  bool get isRunning;\n\n  Future<void> start(BitunixApiCredentials credentials);\n  Future<void> stop();\n  Future<void> dispose();\n}\n\nfinal class BitunixPrivateWebSocketClient implements PrivateTruthStreamClient {\n''',
)

models = ROOT / 'lib/features/auto_trade/domain/private_truth_models.dart'
marker = 'final class PrivateTruthMetrics {\n'
models_text = models.read_text()
if 'final class PrivateTruthFillConfirmation' not in models_text:
    fill_model = '''final class PrivateTruthFillConfirmation {\n  const PrivateTruthFillConfirmation({\n    required this.order,\n    required this.position,\n  });\n\n  final PrivateOrderUpdate order;\n  final PrivatePositionUpdate position;\n}\n\n'''
    if marker not in models_text:
        raise SystemExit('metrics marker missing')
    models.write_text(models_text.replace(marker, fill_model + marker, 1))

coordinator = ROOT / 'lib/features/auto_trade/application/private_truth_coordinator.dart'
replace_once(
    coordinator,
    '  final BitunixPrivateWebSocketClient _socketClient;\n',
    '  final PrivateTruthStreamClient _socketClient;\n',
)
coordinator_text = coordinator.read_text()
method_marker = '  Future<void> _verifyRest() async {\n'
if 'waitForFullFill({' not in coordinator_text:
    method = r'''  Future<PrivateTruthFillConfirmation?> waitForFullFill({
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
      final order = matchingOrders.where(
        (item) => item.orderStatus.toUpperCase() == 'FILLED',
      ).firstOrNull;
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

'''
    if method_marker not in coordinator_text:
        raise SystemExit('coordinator method marker missing')
    coordinator.write_text(
        coordinator_text.replace(method_marker, method + method_marker, 1)
    )

service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
old_first = r'''          BitunixOrderDetail? detail;
          BitunixLivePosition? position;
          for (var attempt = 0; attempt < 10; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 750));
            detail = await exchange.fetchOrderDetail(
              orderId: placed.orderId,
              credentials: credentials,
            );
            final matches = await exchange.fetchPositions(
              credentials,
              symbol: idea.symbol,
            );
            position = matches.firstOrNull;
            if (detail.fullyFilled && position != null) break;
          }
'''
new_first = r'''          BitunixOrderDetail? detail;
          BitunixLivePosition? position;
          final hotFill = await privateTruth.waitForFullFill(
            orderId: placed.orderId,
            clientId: placed.clientId,
            symbol: idea.symbol,
          );
          if (hotFill != null) {
            detail = _orderDetailFromPrivateFill(hotFill);
            position = _livePositionFromPrivateFill(hotFill);
            _auditEvent(
              'entry_fill_ws_confirmed',
              'Entry fill and position were confirmed by the authenticated private WebSocket.',
              symbol: idea.symbol,
            );
          } else {
            final fallback = await _fetchEntryRestState(
              exchange: exchange,
              credentials: credentials,
              orderId: placed.orderId,
              symbol: idea.symbol,
            );
            detail = fallback.detail;
            position = fallback.position;
            _auditEvent(
              'entry_fill_rest_fallback',
              'Private WebSocket fill confirmation timed out; one bounded REST reconciliation was used.',
              symbol: idea.symbol,
            );
          }
'''
replace_once(service, old_first, new_first)
old_second = r'''            for (var attempt = 0; attempt < 10; attempt++) {
              await Future<void>.delayed(const Duration(milliseconds: 750));
              detail = await exchange.fetchOrderDetail(
                orderId: placed.orderId,
                credentials: credentials,
              );
              final matches = await exchange.fetchPositions(
                credentials,
                symbol: idea.symbol,
              );
              position = matches.firstOrNull;
              if (detail.fullyFilled && position != null) break;
              if (detail.status == 'CANCELED') break;
            }
'''
new_second = r'''            await Future<void>.delayed(const Duration(milliseconds: 500));
            final cleanupState = await _fetchEntryRestState(
              exchange: exchange,
              credentials: credentials,
              orderId: placed.orderId,
              symbol: idea.symbol,
            );
            detail = cleanupState.detail;
            position = cleanupState.position;
'''
replace_once(service, old_second, new_second)
service_text = service.read_text()
helper_marker = '  Future<void> _recoverVerifiedQuantaraOrphans(\n'
if '_fetchEntryRestState({' not in service_text:
    helper = r'''  Future<({BitunixOrderDetail detail, BitunixLivePosition? position})>
  _fetchEntryRestState({
    required BitunixLocalLiveApiClient exchange,
    required BitunixApiCredentials credentials,
    required String orderId,
    required String symbol,
  }) async {
    final values = await Future.wait<Object>([
      exchange.fetchOrderDetail(orderId: orderId, credentials: credentials),
      exchange.fetchPositions(credentials, symbol: symbol),
    ]);
    final detail = values[0] as BitunixOrderDetail;
    final positions = values[1] as List<BitunixLivePosition>;
    return (detail: detail, position: positions.firstOrNull);
  }

  BitunixOrderDetail _orderDetailFromPrivateFill(
    PrivateTruthFillConfirmation confirmation,
  ) => BitunixOrderDetail(
    orderId: confirmation.order.orderId,
    clientId: confirmation.order.clientId,
    symbol: confirmation.order.symbol,
    quantity: confirmation.order.quantity,
    filledQuantity: confirmation.order.dealAmount,
    status: confirmation.order.orderStatus.toUpperCase(),
    fee: confirmation.order.fee,
    realizedPnl: 0,
  );

  BitunixLivePosition _livePositionFromPrivateFill(
    PrivateTruthFillConfirmation confirmation,
  ) => BitunixLivePosition(
    positionId: confirmation.position.positionId,
    symbol: confirmation.position.symbol,
    quantity: confirmation.position.quantity,
    side: confirmation.position.side,
    marginMode: confirmation.position.marginMode,
    positionMode: confirmation.position.positionMode,
    leverage: confirmation.position.leverage,
    averageOpenPrice: confirmation.order.averagePrice,
    realizedPnl: confirmation.position.realizedPnl,
    unrealizedPnl: confirmation.position.unrealizedPnl,
    fee: confirmation.position.fee + confirmation.order.fee,
    funding: confirmation.position.funding,
  );

'''
    if helper_marker not in service_text:
        raise SystemExit('service helper marker missing')
    service.write_text(service_text.replace(helper_marker, helper + helper_marker, 1))
