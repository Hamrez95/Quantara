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
text = text.replace(old, new, 1)

old = """    \"          orderId: managed.targetOrderIds[index],\\n\"
    \"          quantity: managed.targetQuantities[index],\\n\",
    \"          exchangeEventId: 'tp-order:$orderId',\\n\"
"""
new = """    \"          orderId: managed.targetOrderIds[index],\\n\"
    \"          quantity: quantity,\\n\",
    \"          exchangeEventId: 'tp-order:$orderId',\\n\"
"""
if text.count(old) != 1:
    raise SystemExit('hotfix script recovered TP quantity anchor changed')
text = text.replace(old, new, 1)

path.write_text(text)
