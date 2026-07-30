import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_request_signer.dart';

void main() {
  test('matches the official two-stage Bitunix SHA-256 example', () {
    final result = BitunixRequestSigner.create(
      nonce: '123456',
      timestamp: '20241120123045',
      apiKey: 'yourApiKey',
      secretKey: 'yourSecretKey',
      query: const {'uid': '200', 'id': '1'},
      body:
          '{"uid":"2899","arr":[{"id":1,"name":"maple"},{"id":2,"name":"lily"}]}',
    );
    expect(
      result.digest,
      '75099831ac6803e9c5b79dd3cde2c3c529b4750bd3508186afdde0dd13599b38',
    );
    expect(
      result.sign,
      '00397cd1e52c7dce3258067324363b6361fabc9178a0912b330c138db8745655',
    );
  });
}
