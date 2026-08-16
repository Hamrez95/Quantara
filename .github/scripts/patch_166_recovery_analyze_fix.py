from pathlib import Path

ROOT = Path('src/client/quantara_app')

classifier = ROOT / 'lib/features/auto_trade/domain/exchange_position_ownership.dart'
text = classifier.read_text()
text = text.replace('historyClear.contains(id)', 'verifiedRecovery.contains(id)')
# Once the stronger q-local/fill-history/protection policy has explicitly
# verified Quantara ownership, adaptive 1-3 TP ladders are valid as long as
# quantity coverage is complete. Unverified/external positions still require
# the conservative legacy 3-TP shape and remain non-adoptable.
text = text.replace(
    'expectedTakeProfitCount: 3,',
    'expectedTakeProfitCount: verifiedRecovery.contains(id) ? 1 : 3,',
)
classifier.write_text(text)

service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
text = service.read_text()
text = text.replace('managed: managed!,', 'managed: managed,')
text = text.replace('_managed.add(managed!);', '_managed.add(managed);')
service.write_text(text)

test = ROOT / 'test/exchange_position_recovery_transaction_test.dart'
text = test.read_text()
marker = "test('risk-adopted retry commits only managed state then clears checkpoint'"
index = text.find(marker)
if index < 0:
    raise SystemExit('risk-adopted retry test marker missing')
prefix, suffix = text[:index], text[index:]
suffix = suffix.replace('checkpoint: durable!,', 'checkpoint: durable,', 1)
test.write_text(prefix + suffix)
