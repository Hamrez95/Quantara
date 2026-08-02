from pathlib import Path

path = Path('src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart')
text = path.read_text(encoding='utf-8')
old = '''      final tp1Quantity = rules.roundQuantityDown(
        quantity * profitPlan.targetFractions[0],
      );
      final tp2Quantity = rules.roundQuantityDown(
        quantity * profitPlan.targetFractions[1],
      );
      final tp3Quantity = rules.roundQuantityDown(
        quantity - tp1Quantity - tp2Quantity,
      );
      final targetQuantities = [tp1Quantity, tp2Quantity, tp3Quantity];
'''
new = '''      final allocation = ProfitProtectionAllocation.allocate(
        totalQuantity: quantity,
        plan: profitPlan,
        roundDown: rules.roundQuantityDown,
      );
      final targetQuantities = allocation.quantities;
'''
if text.count(old) != 1:
    raise RuntimeError('Expected exactly one staged-target allocation block.')
text = text.replace(old, new, 1)
old_fraction = '          targetFractions: profitPlan.targetFractions,\n'
new_fraction = '          targetFractions: allocation.actualFractions,\n'
if text.count(old_fraction) != 1:
    raise RuntimeError('Expected exactly one managed target-fraction assignment.')
text = text.replace(old_fraction, new_fraction, 1)
path.write_text(text, encoding='utf-8')
