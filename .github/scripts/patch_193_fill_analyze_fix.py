from pathlib import Path

root = Path('src/client/quantara_app')
service = root / 'lib/features/auto_trade/application/local_live_trade_service.dart'
text = service.read_text()
needle = "    final exchange = _exchange!;\n    final client = http.Client();\n"
replacement = "    final exchange = _exchange!;\n    final privateTruth = _privateTruth;\n    if (privateTruth == null || !privateTruth.isRunning) {\n      _entriesEnabled = false;\n      _entryBlockReason = 'privateAccountState';\n      _auditEvent(\n        'private_truth_entry_block',\n        'Private WebSocket truth is not active; no new order can be submitted.',\n      );\n      return;\n    }\n    final client = http.Client();\n"
if needle not in text:
    raise SystemExit('scan entry prelude not found')
text = text.replace(needle, replacement, 1)
text = text.replace(
    'if (detail == null || !detail.fullyFilled || position == null)',
    'if (!detail.fullyFilled || position == null)',
)
text = text.replace("detail?.status == 'CANCELED'", "detail.status == 'CANCELED'")
service.write_text(text)

client = root / 'lib/features/auto_trade/data/bitunix_private_websocket_client.dart'
text = client.read_text()
for signature in [
    '  Stream<PrivateTruthEvent> get events =>',
    '  Stream<PrivateWsClientStatus> get statuses =>',
    '  bool get isRunning =>',
    '  Future<void> start(BitunixApiCredentials credentials) async {',
    '  Future<void> stop() async {',
    '  Future<void> dispose() async {',
]:
    if signature not in text:
        raise SystemExit(f'override target not found: {signature}')
    text = text.replace(signature, '  @override\n' + signature, 1)
client.write_text(text)
