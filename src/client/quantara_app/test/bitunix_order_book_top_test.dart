import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_order_book_top.dart';
import 'package:quantara_app/features/auto_trade/domain/execution_quality_models.dart';

void main() {
  test('long uses best ask and short uses best bid', () {
    final book = BitunixOrderBookTop.fromApiPayload({
      'data': {
        'bids': [
          ['99.9', '4.2'],
          ['99.8', '3.1'],
        ],
        'asks': [
          ['100.1', '2.5'],
          ['100.2', '1.8'],
        ],
      },
    });

    expect(book.bestBid, 99.9);
    expect(book.bestAsk, 100.1);
    expect(book.executablePriceFor(ExecutionSide.long), 100.1);
    expect(book.executablePriceFor(ExecutionSide.short), 99.9);
  });

  test('only the top level determines executable price', () {
    final book = BitunixOrderBookTop.fromApiPayload({
      'data': {
        'bids': [
          [99.9, 1],
          [1, 999999],
        ],
        'asks': [
          [100.1, 1],
          [999999, 999999],
        ],
      },
    });

    expect(book.executablePriceFor(ExecutionSide.long), 100.1);
    expect(book.executablePriceFor(ExecutionSide.short), 99.9);
  });

  test('empty or malformed sides fail closed', () {
    expect(
      () => BitunixOrderBookTop.fromApiPayload({
        'data': {
          'bids': const <Object?>[],
          'asks': [
            ['100.1', '1'],
          ],
        },
      }),
      throwsFormatException,
    );
    expect(
      () => BitunixOrderBookTop.fromApiPayload({
        'data': {
          'bids': [
            ['99.9'],
          ],
          'asks': [
            ['100.1', '1'],
          ],
        },
      }),
      throwsFormatException,
    );
  });

  test('nonpositive or nonnumeric top prices fail closed', () {
    expect(
      () => BitunixOrderBookTop.fromApiPayload({
        'data': {
          'bids': [
            ['0', '1'],
          ],
          'asks': [
            ['100.1', '1'],
          ],
        },
      }),
      throwsFormatException,
    );
    expect(
      () => BitunixOrderBookTop.fromApiPayload({
        'data': {
          'bids': [
            ['99.9', '1'],
          ],
          'asks': [
            ['not-a-price', '1'],
          ],
        },
      }),
      throwsFormatException,
    );
  });

  test('crossed or locked book fails closed', () {
    expect(
      () => BitunixOrderBookTop.fromApiPayload({
        'data': {
          'bids': [
            ['100.1', '1'],
          ],
          'asks': [
            ['100.0', '1'],
          ],
        },
      }),
      throwsFormatException,
    );
    expect(
      () => BitunixOrderBookTop.fromApiPayload({
        'data': {
          'bids': [
            ['100.0', '1'],
          ],
          'asks': [
            ['100.0', '1'],
          ],
        },
      }),
      throwsFormatException,
    );
  });
}
