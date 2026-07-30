import 'dart:convert';

import 'package:crypto/crypto.dart';

final class BitunixSignature {
  const BitunixSignature({required this.digest, required this.sign});

  final String digest;
  final String sign;
}

abstract final class BitunixRequestSigner {
  static BitunixSignature create({
    required String nonce,
    required String timestamp,
    required String apiKey,
    required String secretKey,
    Map<String, String> query = const {},
    String body = '',
  }) {
    final entries = query.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final queryString = entries
        .map((entry) => '${entry.key}${entry.value}')
        .join();
    final digest = _sha256('$nonce$timestamp$apiKey$queryString$body');
    return BitunixSignature(digest: digest, sign: _sha256('$digest$secretKey'));
  }

  static String _sha256(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
