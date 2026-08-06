from pathlib import Path

path = Path('src/client/quantara_app/test/local_live_issue_169_core_test.dart')
text = path.read_text(encoding='utf-8')
old = "    expect(source, contains(\"final key = '${idea.symbol}|${idea.strategy.name}'\"));\n"
new = "    expect(\n      source,\n      contains(r\"final key = '${idea.symbol}|${idea.strategy.name}'\"),\n    );\n"
if text.count(old) != 1:
    raise RuntimeError(f'expected one assertion match, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
