from pathlib import Path

path = Path(__file__).resolve().parents[1] / 'src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_analysis.dart'
text = path.read_text()
old = "ButtonSegment(value: timeframe, label: Text(timeframe)),"
new = "ButtonSegment(\n                        value: timeframe,\n                        label: Text(\n                          timeframe,\n                          key: ValueKey('alpha-timeframe-$timeframe'),\n                        ),\n                      ),"
if new not in text:
    if old not in text:
        raise SystemExit('timeframe segment target not found')
    path.write_text(text.replace(old, new, 1))
