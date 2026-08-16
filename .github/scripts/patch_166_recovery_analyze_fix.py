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

classifier_test = ROOT / 'test/exchange_position_ownership_test.dart'
text = classifier_test.read_text()
if 'adaptive one-target Quantara recovery remains recoverable' not in text:
    insertion = r'''
  test('adaptive one-target Quantara recovery remains recoverable', () {
    const adaptiveProtection = [
      AutoTradeProtectionOrder.stopLoss(
        exchangeId: 'sl-1',
        positionId: 'p-1',
        symbol: 'BTCUSDT',
        price: 95000,
        quantity: 1,
      ),
      AutoTradeProtectionOrder.takeProfit(
        exchangeId: 'tp-1',
        positionId: 'p-1',
        symbol: 'BTCUSDT',
        price: 103000,
        quantity: 1,
      ),
    ];
    final result = ExchangePositionOwnershipClassifier.classify(
      account: account(protectionOrders: adaptiveProtection),
      managedPositions: const [],
      verifiedQuantaraRecoveryPositionIds: const ['p-1'],
    );

    expect(result.positions.single.kind,
        ExchangePositionOwnershipKind.recoverableOrphan);
    expect(result.positions.single.recoverable, isTrue);
    expect(result.blocksNewEntries, isTrue);
  });
'''
    final closing = text.rfind('\n}')
    if closing < 0:
        raise SystemExit('classifier test closing brace missing')
    text = text[:closing] + insertion + text[closing:]
classifier_test.write_text(text)

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
