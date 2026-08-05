from pathlib import Path

path = Path('.github/scripts/feat165_historical_journal_backfill.py')
text = path.read_text()
old = "    marker = '''  test('journal confirmation and closed lifecycle are neutral, not profit green', () {'''"
new = "    marker = '''  test(\n    'journal confirmation and closed lifecycle are neutral, not profit green',\n    () {'''"
count = text.count(old)
if count not in (0, 1):
    raise SystemExit(f'expected zero or one source-test anchor definition, found {count}')
if count == 1:
    path.write_text(text.replace(old, new, 1))
