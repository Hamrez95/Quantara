import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class BitunixWebSocket {
  Future<void> get ready;

  Stream<Object?> get messages;

  void send(String message);

  Future<void> close({int? code, String? reason});
}

abstract interface class BitunixWebSocketConnector {
  BitunixWebSocket connect(Uri uri);
}

final class DefaultBitunixWebSocketConnector
    implements BitunixWebSocketConnector {
  const DefaultBitunixWebSocketConnector();

  @override
  BitunixWebSocket connect(Uri uri) =>
      WebSocketChannelBitunixAdapter(WebSocketChannel.connect(uri));
}

final class WebSocketChannelBitunixAdapter implements BitunixWebSocket {
  WebSocketChannelBitunixAdapter(this._channel);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<Object?> get messages => _channel.stream.cast<Object?>();

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  Future<void> close({int? code, String? reason}) async {
    await _channel.sink.close(code, reason);
  }
}
