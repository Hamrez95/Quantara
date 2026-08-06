from pathlib import Path

root = Path('src/client/quantara_app')

test_path = root / 'test/local_live_issue_169_core_test.dart'
test = test_path.read_text(encoding='utf-8')
old_assertion = "    expect(source, contains(\"final key = '${idea.symbol}|${idea.strategy.name}'\"));\n"
new_assertion = "    expect(\n      source,\n      contains(r\"final key = '${idea.symbol}|${idea.strategy.name}'\"),\n    );\n"
if test.count(old_assertion) != 1:
    raise RuntimeError(
        f'expected one strategy assertion match, found {test.count(old_assertion)}'
    )
test_path.write_text(test.replace(old_assertion, new_assertion, 1), encoding='utf-8')

service_path = root / 'lib/features/auto_trade/application/local_live_trade_service.dart'
service = service_path.read_text(encoding='utf-8')
old_guard = """            if (!idea.isActionable ||
                occupiedSymbols.contains(idea.symbol.trim().toUpperCase())) {
              continue;
            }
"""
new_guard = """            final symbolAvailable = !occupiedSymbols.contains(
              idea.symbol.trim().toUpperCase(),
            );
            if (!idea.isActionable || !symbolAvailable) {
              continue;
            }
"""
if service.count(old_guard) != 1:
    raise RuntimeError(
        f'expected one occupied-symbol guard match, found {service.count(old_guard)}'
    )
service_path.write_text(service.replace(old_guard, new_guard, 1), encoding='utf-8')
