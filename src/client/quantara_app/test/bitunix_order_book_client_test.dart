import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_order_book_client.dart';

void main() {
  test('fetches only one top-of-book level for the normalized symbol', () async {
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        '{"code":0,"data":{"asks":[["100.1","2"]],"bids":[["99.9","3"]]},"msg":"Success"}',
        200,
      );
    });
    final orderBook = BitunixOrderBookClient(client: client);

    final top = await orderBook.fetchTopOfBook(' btcusdt ');

    expect(requestedUri?.host, 'fapi.bitunix.com');
    expect(requestedUri?.path, '/api/v1/futures/market/depth');
    expect(requestedUri?.queryParameters['symbol'], 'BTCUSDT');
    expect(requestedUri?.queryParameters['limit'], '1');
    expect(top.bestBid, 99.9);
    expect(top.bestAsk, 100.1);
  });

  test('non-success HTTP and exchange codes fail closed', () async {
    final httpFailure = BitunixOrderBookClient(
      client: MockClient((request) async => http.Response('unavailable', 503)),
    );
    final exchangeFailure = BitunixOrderBookClient(
      client: MockClient(
        (request) async => http.Response('{"code":10001,"msg":"rejected"}', 200),
      ),
    );

    expect(
      () => httpFailure.fetchTopOfBook('BTCUSDT'),
      throwsFormatException,
    );
    expect(
      () => exchangeFailure.fetchTopOfBook('BTCUSDT'),
      throwsFormatException,
    );
  });

  test('malformed JSON and malformed depth fail closed', () async {
    final invalidJson = BitunixOrderBookClient(
      client: MockClient((request) async => http.Response('{', 200)),
    );
    final invalidDepth = BitunixOrderBookClient(
      client: MockClient(
        (request) async => http.Response(
          '{"code":0,"data":{"asks":[],"bids":[["99.9","3"]]}}',
          200,
        ),
      ),
    );

    expect(
      () => invalidJson.fetchTopOfBook('BTCUSDT'),
      throwsFormatException,
    );
    expect(
      () => invalidDepth.fetchTopOfBook('BTCUSDT'),
      throwsFormatException,
    );
  });

  test('empty symbol fails before making a request', () async {
    var requestCount = 0;
    final orderBook = BitunixOrderBookClient(
      client: MockClient((request) async {
        requestCount += 1;
        return http.Response('{}', 200);
      }),
    );

    expect(() => orderBook.fetchTopOfBook('   '), throwsFormatException);
    expect(requestCount, 0);
  });
}
