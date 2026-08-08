from pathlib import Path

path = Path('src/client/quantara_app/lib/features/auto_trade/domain/trading_pnl_projection.dart')
text = path.read_text()
old = """  final values = metrics.toList(growable: false);\n  if (values.any((item) => !item.isAvailable)) {\n    return TradingPnlMetric.unavailable(\n"""
new = """  final values = metrics.toList(growable: false);\n  final hasUnavailableComponent = verified\n      ? values.any((item) => item.value == null)\n      : values.any((item) => !item.isAvailable);\n  if (hasUnavailableComponent) {\n    return TradingPnlMetric.unavailable(\n"""
if old not in text:
    raise SystemExit('aggregate target not found')
path.write_text(text.replace(old, new, 1))
print('Issue #172 aggregate follow-up applied.')
