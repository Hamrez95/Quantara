from pathlib import Path

path = Path('src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart')
text = path.read_text()
old = '''                await exchange.closePositionReduceOnly(
                  position: position,
                  clientId: '$clientId-partial-close',
                  credentials: credentials,
                );
                _auditEvent(
                  'partial_fill_closed',
                  'Unresolved partial fill was closed after entry cancellation.',
                  symbol: idea.symbol,
                );
              }
              if (position == null && detail.status == 'CANCELED') {'''
new = '''                await exchange.closePositionReduceOnly(
                  position: position,
                  clientId: '$clientId-partial-close',
                  credentials: credentials,
                );
                await Future<void>.delayed(const Duration(milliseconds: 400));
                final postCloseState = await _fetchEntryRestState(
                  exchange: exchange,
                  credentials: credentials,
                  orderId: placed.orderId,
                  symbol: idea.symbol,
                  expectedPositionSide: idea.direction == TradeDirection.long
                      ? 'LONG'
                      : 'SHORT',
                );
                detail = postCloseState.detail;
                position = postCloseState.position;
                if (PartialFillCloseConfirmationPolicy.provesFlat(
                  orderStatus: detail.status,
                  position: position,
                )) {
                  _auditEvent(
                    'partial_fill_closed',
                    'Partial-fill close was exchange-confirmed flat after entry cancellation.',
                    symbol: idea.symbol,
                  );
                } else {
                  _auditEvent(
                    'partial_fill_close_unconfirmed',
                    'Partial-fill close was submitted but exchange truth still shows exposure; risk remains ambiguous.',
                    symbol: idea.symbol,
                  );
                }
              }
              if (PartialFillCloseConfirmationPolicy.provesFlat(
                orderStatus: detail.status,
                position: position,
              )) {'''
if old not in text:
    raise SystemExit('partial-close anchor not found')
text = text.replace(old, new, 1)
anchor = "import 'local_live_portfolio_execution_guard.dart';\n"
line = "import 'partial_fill_close_confirmation.dart';\n"
if line not in text:
    text = text.replace(anchor, anchor + line, 1)
path.write_text(text)

policy = Path('src/client/quantara_app/lib/features/auto_trade/application/partial_fill_close_confirmation.dart')
policy.write_text("""import '../data/bitunix_local_live_api_client.dart';

abstract final class PartialFillCloseConfirmationPolicy {
  static bool provesFlat({
    required String orderStatus,
    required BitunixLivePosition? position,
  }) => orderStatus.trim().toUpperCase() == 'CANCELED' && position == null;
}
""")

test = Path('src/client/quantara_app/test/partial_fill_close_confirmation_test.dart')
test.write_text("""import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/partial_fill_close_confirmation.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';

void main() {
  const openPosition = BitunixLivePosition(
    positionId: 'position-1',
    symbol: 'BTCUSDT',
    quantity: 0.01,
    side: 'LONG',
    marginMode: 'ISOLATION',
    positionMode: 'ONE_WAY',
    leverage: 3,
    averageOpenPrice: 100000,
    realizedPnl: 0,
    unrealizedPnl: 0,
    fee: 0,
    funding: 0,
  );

  test('canceled entry plus no position proves flat', () {
    expect(
      PartialFillCloseConfirmationPolicy.provesFlat(
        orderStatus: 'CANCELED',
        position: null,
      ),
      isTrue,
    );
  });

  test('canceled entry with remaining exposure is not flat', () {
    expect(
      PartialFillCloseConfirmationPolicy.provesFlat(
        orderStatus: 'CANCELED',
        position: openPosition,
      ),
      isFalse,
    );
  });

  test('non-canceled order without position is not sufficient proof', () {
    expect(
      PartialFillCloseConfirmationPolicy.provesFlat(
        orderStatus: 'PARTIALLY_FILLED',
        position: null,
      ),
      isFalse,
    );
  });
}
""")
