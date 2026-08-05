from pathlib import Path

path = Path(
    'src/client/quantara_app/lib/features/auto_trade/data/bitunix_pnl_mapper.dart'
)
text = path.read_text()
old = '''          final openedAt = item.openedAt;
          if (openedAt != null && at.isBefore(openedAt.toUtc())) return false;'''
new = '''          final openedAt = item.openedAt;
          if (openedAt != null && at.isBefore(openedAt.toUtc())) {
            return false;
          }'''
count = text.count(old)
if count not in (0, 2):
    raise SystemExit(f'expected zero or two mapper lint anchors, found {count}')
if count == 2:
    path.write_text(text.replace(old, new))
