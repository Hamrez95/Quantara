from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'src/client/quantara_app'


def replace_once(path: Path, old: str, new: str, already_present: str) -> None:
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new, 1))
        return
    if already_present not in text:
        raise SystemExit(f'Expected source block was not found in {path}.')


page = CLIENT / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
text = page.read_text()
marker = "part 'owner_alpha_auto_trade.dart';"
support = "part 'owner_alpha_auto_trade_support.dart';"
if support not in text:
    text = text.replace(marker, marker + '\n' + support, 1)
page.write_text(text)

auto_trade = (
    CLIENT
    / 'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
)
auto_trade.write_text(
    auto_trade.read_text().replace(
        'Icons.cloud_lock_outlined',
        'Icons.cloud_off_outlined',
    )
)

client = (
    CLIENT
    / 'lib/features/auto_trade/data/bitunix_local_live_api_client.dart'
)
replace_once(
    client,
    '''  Future<BitunixPlacedOrder> closePositionReduceOnly({
    required BitunixLivePosition position,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/trade/place_order',
      SplayTreeMap<String, Object?>.from({
        'clientId': clientId,
        'orderType': 'MARKET',
        'positionId': position.positionId,
        'qty': _decimal(position.quantity.abs()),
        'reduceOnly': true,
        'side': position.side.toUpperCase() == 'LONG' ? 'SELL' : 'BUY',
        'symbol': position.symbol,
        'tradeSide': 'CLOSE',
      }),
      credentials,
    );
    final data = _firstMap(response['data']);
    if (data == null) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not return an emergency close order ID.',
      );
    }
    return BitunixPlacedOrder(
      orderId: _string(data['orderId']),
      clientId: _string(data['clientId'], fallback: clientId),
    );
  }
''',
    '''  Future<BitunixPlacedOrder> closePositionReduceOnly({
    required BitunixLivePosition position,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/trade/flash_close_position',
      SplayTreeMap<String, Object?>.from({
        'positionId': position.positionId,
      }),
      credentials,
    );
    final data = _firstMap(response['data']);
    final positionId = _string(data?['positionId']);
    if (positionId.isEmpty) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not confirm the emergency position close.',
      );
    }
    return BitunixPlacedOrder(
      orderId: positionId,
      clientId: clientId,
    );
  }
''',
    '/api/v1/futures/trade/flash_close_position',
)

service = (
    CLIENT
    / 'lib/features/auto_trade/application/local_live_trade_service.dart'
)
replace_once(
    service,
    '''      final tp1Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp2Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp3Quantity = rules.roundQuantityDown(
        quantity - tp1Quantity - tp2Quantity,
      );
      final targetQuantities = [tp1Quantity, tp2Quantity, tp3Quantity];
      if (targetQuantities.any(
        (targetQuantity) => targetQuantity < rules.minimumQuantity,
      )) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-invalid-ladder-close',
          credentials: credentials,
        );
        throw const LocalLiveTradeSafeException(
          'Filled quantity could not be split into three valid exchange targets and was closed.',
        );
      }
      for (var index = 0; index < 3; index++) {
        await exchange.placePartialTakeProfit(
          symbol: idea.symbol,
          positionId: position.positionId,
          triggerPrice: rules.roundPrice(idea.targets[index]),
          quantity: targetQuantities[index],
          credentials: credentials,
        );
      }
      List<BitunixPendingProtection> confirmedProtection = const [];
      for (var attempt = 0; attempt < 6; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        confirmedProtection = await exchange.fetchPendingProtection(
          credentials,
          symbol: idea.symbol,
          positionId: position.positionId,
        );
        final fullStopConfirmed = confirmedProtection.any(
          (item) => item.stopLossPrice > 0,
        );
        final targetCount = confirmedProtection
            .where(
              (item) =>
                  item.takeProfitPrice > 0 &&
                  item.takeProfitQuantity >= rules.minimumQuantity,
            )
            .length;
        if (fullStopConfirmed && targetCount >= 3) break;
      }
      final fullStopConfirmed = confirmedProtection.any(
        (item) => item.stopLossPrice > 0,
      );
      final targetCount = confirmedProtection
          .where(
            (item) =>
                item.takeProfitPrice > 0 &&
                item.takeProfitQuantity >= rules.minimumQuantity,
          )
          .length;
      if (!fullStopConfirmed || targetCount < 3) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-incomplete-protection-close',
          credentials: credentials,
        );
        throw const LocalLiveTradeSafeException(
          'The complete SL/TP ladder was not confirmed; emergency close was submitted.',
        );
      }
''',
    '''      final tp1Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp2Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp3Quantity = rules.roundQuantityDown(
        quantity - tp1Quantity - tp2Quantity,
      );
      final targetQuantities = [tp1Quantity, tp2Quantity, tp3Quantity];
      if (targetQuantities.any(
        (targetQuantity) => targetQuantity < rules.minimumQuantity,
      )) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-invalid-ladder-close',
          credentials: credentials,
        );
        throw const LocalLiveTradeSafeException(
          'Filled quantity could not be split into three valid exchange targets and was closed.',
        );
      }
      try {
        for (var index = 0; index < 3; index++) {
          await exchange.placePartialTakeProfit(
            symbol: idea.symbol,
            positionId: position.positionId,
            triggerPrice: rules.roundPrice(idea.targets[index]),
            quantity: targetQuantities[index],
            credentials: credentials,
          );
        }
        List<BitunixPendingProtection> confirmedProtection = const [];
        for (var attempt = 0; attempt < 6; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          confirmedProtection = await exchange.fetchPendingProtection(
            credentials,
            symbol: idea.symbol,
            positionId: position.positionId,
          );
          final fullStopConfirmed = confirmedProtection.any(
            (item) => item.stopLossPrice > 0,
          );
          final targetCount = confirmedProtection
              .where(
                (item) =>
                    item.takeProfitPrice > 0 &&
                    item.takeProfitQuantity >= rules.minimumQuantity,
              )
              .length;
          if (fullStopConfirmed && targetCount >= 3) break;
        }
        final fullStopConfirmed = confirmedProtection.any(
          (item) => item.stopLossPrice > 0,
        );
        final targetCount = confirmedProtection
            .where(
              (item) =>
                  item.takeProfitPrice > 0 &&
                  item.takeProfitQuantity >= rules.minimumQuantity,
            )
            .length;
        if (!fullStopConfirmed || targetCount < 3) {
          throw const LocalLiveTradeSafeException(
            'The complete SL/TP ladder was not confirmed.',
          );
        }
      } on Object catch (error) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-incomplete-protection-close',
          credentials: credentials,
        );
        if (error is LocalLiveTradeSafeException) rethrow;
        throw const LocalLiveTradeSafeException(
          'TP ladder placement failed; emergency close was submitted.',
        );
      }
''',
    'TP ladder placement failed; emergency close was submitted',
)
