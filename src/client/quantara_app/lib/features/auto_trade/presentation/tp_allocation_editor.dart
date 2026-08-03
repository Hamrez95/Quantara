import 'package:flutter/material.dart';

import '../../owner_alpha/domain/profit_protection_policy.dart';

class TpAllocationEditor extends StatelessWidget {
  const TpAllocationEditor({
    required this.allocation,
    required this.onChanged,
    required this.persian,
    this.enabled = true,
    super.key,
  });

  final ProfitProtectionTargetAllocation allocation;
  final ValueChanged<ProfitProtectionTargetAllocation> onChanged;
  final bool persian;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final values = [
      (allocation.tp1Fraction * 100).round(),
      (allocation.tp2Fraction * 100).round(),
      (allocation.tp3Fraction * 100).round(),
    ];
    return Semantics(
      container: true,
      label: persian ? 'تقسیم اهداف سود' : 'Take-profit allocation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < 3; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      persian
                          ? 'بستن در هدف ${index + 1}'
                          : 'Close at TP${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('tp${index + 1}-minus'),
                    onPressed: enabled
                        ? () => onChanged(_adjust(values, index, -5))
                        : null,
                    tooltip: persian ? '۵٪ کمتر' : 'Decrease 5%',
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${values[index]}%',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('tp${index + 1}-plus'),
                    onPressed: enabled
                        ? () => onChanged(_adjust(values, index, 5))
                        : null,
                    tooltip: persian ? '۵٪ بیشتر' : 'Increase 5%',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              persian ? 'جمع: ۱۰۰٪' : 'Total: 100%',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  static ProfitProtectionTargetAllocation _adjust(
    List<int> source,
    int index,
    int delta,
  ) {
    final values = List<int>.of(source);
    if (delta > 0) {
      final donorOrder = index == 0
          ? const [2, 1]
          : index == 1
          ? const [2, 0]
          : const [1, 0];
      final donor = donorOrder.firstWhere(
        (candidate) => values[candidate] >= 10,
        orElse: () => -1,
      );
      if (donor >= 0 && values[index] < 90) {
        values[index] += 5;
        values[donor] -= 5;
      }
    } else if (values[index] > 5) {
      final receiver = index == 0 ? 1 : 0;
      values[index] -= 5;
      values[receiver] += 5;
    }
    return ProfitProtectionTargetAllocation.checked(
      tp1Fraction: values[0] / 100,
      tp2Fraction: values[1] / 100,
      tp3Fraction: values[2] / 100,
    );
  }
}
