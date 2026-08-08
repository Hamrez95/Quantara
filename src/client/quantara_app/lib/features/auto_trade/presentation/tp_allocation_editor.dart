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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _preset(
                context,
                key: 'tp-preset-1',
                label: '100 / 0 / 0',
                values: const [100, 0, 0],
              ),
              _preset(
                context,
                key: 'tp-preset-2',
                label: '80 / 20 / 0',
                values: const [80, 20, 0],
              ),
              _preset(
                context,
                key: 'tp-preset-3',
                label: '80 / 15 / 5',
                values: const [80, 15, 5],
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                    onPressed: enabled && _canDecrease(values, index)
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
                    onPressed: enabled && _canIncrease(values, index)
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
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                Text(
                  persian ? 'جمع: ۱۰۰٪' : 'Total: 100%',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  persian
                      ? '${allocation.activeTargetCount} هدف فعال'
                      : '${allocation.activeTargetCount} active target(s)',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preset(
    BuildContext context, {
    required String key,
    required String label,
    required List<int> values,
  }) {
    final selected =
        (allocation.tp1Fraction * 100).round() == values[0] &&
        (allocation.tp2Fraction * 100).round() == values[1] &&
        (allocation.tp3Fraction * 100).round() == values[2];
    return ChoiceChip(
      key: ValueKey(key),
      label: Text(label, textDirection: TextDirection.ltr),
      selected: selected,
      onSelected: enabled ? (_) => onChanged(_fromValues(values)) : null,
    );
  }

  static bool _canDecrease(List<int> values, int index) {
    if (index == 0) return values[0] > 5;
    if (index == 1) return values[1] > 0 && values[2] == 0;
    return values[2] > 0;
  }

  static bool _canIncrease(List<int> values, int index) {
    if (values[index] >= 100) return false;
    if (index == 2 && values[1] == 0) return false;
    return values.asMap().entries.any(
      (entry) => entry.key != index && entry.value >= 5,
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
        (candidate) => values[candidate] >= 5,
        orElse: () => -1,
      );
      if (donor >= 0 && !(index == 2 && values[1] == 0)) {
        values[index] += 5;
        values[donor] -= 5;
      }
    } else if (_canDecrease(values, index)) {
      final receiver = index == 2 ? 1 : 0;
      values[index] -= 5;
      values[receiver] += 5;
    }
    return _fromValues(values);
  }

  static ProfitProtectionTargetAllocation _fromValues(List<int> values) =>
      ProfitProtectionTargetAllocation.checked(
        tp1Fraction: values[0] / 100,
        tp2Fraction: values[1] / 100,
        tp3Fraction: values[2] / 100,
      );
}
