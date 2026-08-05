from pathlib import Path

path = Path('.github/scripts/apply_eth_stop_hotfix.py')
text = path.read_text()
old = """    count=1,
)
replace_exact(
    observer,
    \"    for (var index = 0; index < managed.targetOrderIds.length; index++) {\\n\"
    \"      await _append(\\n\"
"""
new = """    count=2,
)
replace_exact(
    observer,
    \"    for (var index = 0; index < managed.targetOrderIds.length; index++) {\\n\"
    \"      await _append(\\n\"
"""
if text.count(old) != 1:
    raise SystemExit('hotfix script observer cardinality anchor changed')
path.write_text(text.replace(old, new, 1))
