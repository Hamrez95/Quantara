from pathlib import Path

path = Path(
    'src/client/quantara_app/test/bitunix_pnl_mapper_physical_canary_test.dart'
)
text = path.read_text()
old = "'mtime': DateTime.utc(2026, 8, 5, 3, 19, 28).millisecondsSinceEpoch,"
new = "'mtime': DateTime.utc(2026, 8, 5, 3, 19).millisecondsSinceEpoch,"
count = text.count(old)
if count not in (0, 1):
    raise SystemExit(f'expected zero or one ambiguous fixture anchor, found {count}')
if count == 1:
    path.write_text(text.replace(old, new, 1))
