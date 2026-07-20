from pathlib import Path

path = Path('src/client/quantara_app/lib/features/cockpit/presentation/cockpit_page.dart')
text = path.read_text(encoding='utf-8')

old = '    return Semantics(\n      button: true,\n      label:'
new = '    return Semantics(\n      label:'
if old not in text:
    raise SystemExit('expected semantics block not found')
text = text.replace(old, new, 1)

old = '          onTap: () {},'
new = '          onTap: null,'
if old not in text:
    raise SystemExit('expected callback not found')
text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
