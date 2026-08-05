from pathlib import Path

ROOT = Path("src/client/quantara_app")

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"anchor missing in {path}: {old[:100]!r}")
    path.write_text(text.replace(old, new, 1))

policy = ROOT / "lib/features/owner_alpha/domain/profit_protection_policy.dart"
replace_once(
    policy,
    """  List<double> get fractions =>
      List.unmodifiable([tp1Fraction, tp2Fraction, tp3Fraction]);

  double get minimumFraction => [
    tp1Fraction,
    tp2Fraction,
    tp3Fraction,
  ].reduce((left, right) => left < right ? left : right);
""",
    """  List<double> get fractions =>
      List.unmodifiable([tp1Fraction, tp2Fraction, tp3Fraction]);

  List<double> get activeFractions =>
      List.unmodifiable(fractions.where((value) => value > 0));

  int get activeTargetCount => activeFractions.length;

  double get minimumActiveFraction => activeFractions.reduce(
    (left, right) => left < right ? left : right,
  );
""",
)
replace_once(
    policy,
    """    final values = [tp1Fraction, tp2Fraction, tp3Fraction];
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (values.any((value) => !value.isFinite || value <= 0) ||
        (total - 1).abs() > 0.000001) {
      throw const FormatException(
        'TP1, TP2 and TP3 must be positive and total exactly 100%.',
      );
    }
""",
    """    final values = [tp1Fraction, tp2Fraction, tp3Fraction];
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final hasGap = tp2Fraction <= 0 && tp3Fraction > 0;
    if (values.any((value) => !value.isFinite || value < 0) ||
        tp1Fraction <= 0 ||
        hasGap ||
        (total - 1).abs() > 0.000001) {
      throw const FormatException(
        'TP1 must be active; TP2 and TP3 may be zero, active targets must be contiguous, and the total must be exactly 100%.',
      );
    }
""",
)
replace_once(
    policy,
    """  double get minimumTargetFraction => targetAllocation.minimumFraction;
""",
    """  double get minimumTargetFraction =>
      targetAllocation.minimumActiveFraction;
""",
)
text = policy.read_text()
if "allocateAdaptive" not in text:
    start = text.index("final class ProfitProtectionAllocation {")
    end = text.index("abstract final class ProfitProtectionPolicy {")
    allocation_class = r"""final class ProfitProtectionAllocation {
  const ProfitProtectionAllocation({
    required this.totalQuantity,
    required this.quantities,
    required this.targetAllocation,
  });

  final double totalQuantity;
  final List<double> quantities;
  final ProfitProtectionTargetAllocation targetAllocation;

  int get activeTargetCount => targetAllocation.activeTargetCount;

  List<double> get actualFractions => List.unmodifiable(
    quantities.map(
      (quantity) => totalQuantity <= 0 ? 0 : quantity / totalQuantity,
    ),
  );

  double get allocatedQuantity =>
      quantities.fold<double>(0, (sum, quantity) => sum + quantity);

  double get residualQuantity {
    final value = totalQuantity - allocatedQuantity;
    return value.abs() <= 0.000000001 ? 0 : value;
  }

  bool isValidFor(double minimumQuantity) {
    if (totalQuantity <= 0 ||
        quantities.length != 3 ||
        !minimumQuantity.isFinite ||
        minimumQuantity <= 0 ||
        residualQuantity < -0.000000001) {
      return false;
    }
    for (var index = 0; index < 3; index++) {
      final fraction = targetAllocation.fractions[index];
      final quantity = quantities[index];
      if (!quantity.isFinite || quantity < 0) return false;
      if (fraction > 0) {
        if (quantity < minimumQuantity) return false;
      } else if (quantity.abs() > 0.000000001) {
        return false;
      }
    }
    return true;
  }

  static ProfitProtectionAllocation allocate({
    required double totalQuantity,
    required ProfitProtectionPlan plan,
    required double Function(double value) roundDown,
  }) {
    final tp2 = plan.targetAllocation.tp2Fraction <= 0
        ? 0.0
        : roundDown(totalQuantity * plan.targetAllocation.tp2Fraction);
    final tp3 = plan.targetAllocation.tp3Fraction <= 0
        ? 0.0
        : roundDown(totalQuantity * plan.targetAllocation.tp3Fraction);
    final tp1 = roundDown(totalQuantity - tp2 - tp3);
    return ProfitProtectionAllocation(
      totalQuantity: totalQuantity,
      quantities: List.unmodifiable([tp1, tp2, tp3]),
      targetAllocation: plan.targetAllocation,
    );
  }

  static ProfitProtectionAllocation allocateAdaptive({
    required double totalQuantity,
    required ProfitProtectionPlan plan,
    required double minimumQuantity,
    required double Function(double value) roundDown,
  }) {
    var effective = plan.targetAllocation;
    for (var attempt = 0; attempt < 3; attempt++) {
      final candidate = allocate(
        totalQuantity: totalQuantity,
        plan: plan.withTargetAllocation(effective),
        roundDown: roundDown,
      );
      if (candidate.isValidFor(minimumQuantity)) return candidate;

      final values = effective.fractions.toList(growable: false);
      var collapsed = false;
      for (var index = 2; index >= 1; index--) {
        final configured = values[index] > 0;
        final undersized =
            configured && candidate.quantities[index] < minimumQuantity;
        if (!undersized) continue;
        values[index - 1] += values[index];
        values[index] = 0;
        effective = ProfitProtectionTargetAllocation.checked(
          tp1Fraction: values[0],
          tp2Fraction: values[1],
          tp3Fraction: values[2],
        );
        collapsed = true;
        break;
      }
      if (!collapsed) return candidate;
    }
    return allocate(
      totalQuantity: totalQuantity,
      plan: plan.withTargetAllocation(effective),
      roundDown: roundDown,
    );
  }
}

"""
    policy.write_text(text[:start] + allocation_class + text[end:])

editor = ROOT / "lib/features/auto_trade/presentation/tp_allocation_editor.dart"
editor.write_text(r"""import 'package:flutter/material.dart';

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
            child: Text(
              persian
                  ? 'جمع: ۱۰۰٪ · ${allocation.activeTargetCount} هدف فعال'
                  : 'Total: 100% · ${allocation.activeTargetCount} active target(s)',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
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
      onSelected: enabled
          ? (_) => onChanged(_fromValues(values))
          : null,
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
""")

remaining = ROOT / "lib/features/auto_trade/domain/remaining_target_protection_policy.dart"
replace_once(
    remaining,
    """      final id = targetOrderIds[index].trim();
      final planned = targetQuantities[index];
      final filled = filledQuantities[index];
      if (id.isEmpty ||
          !planned.isFinite ||
          planned <= 0 ||
          !filled.isFinite ||
          filled < 0 ||
          filled > planned + quantityTolerance) {
        return false;
      }
""",
    """      final id = targetOrderIds[index].trim();
      final planned = targetQuantities[index];
      final filled = filledQuantities[index];
      if (!planned.isFinite ||
          planned < 0 ||
          !filled.isFinite ||
          filled < 0 ||
          filled > planned + quantityTolerance) {
        return false;
      }
      if (planned <= quantityTolerance) {
        if (id.isNotEmpty || filled > quantityTolerance) return false;
        continue;
      }
      if (id.isEmpty) return false;
""",
)

service = ROOT / "lib/features/auto_trade/application/local_live_trade_service.dart"
replace_once(
    service,
    """      if (quantity < rules.minimumQuantity / profitPlan.minimumTargetFraction ||
          quantity > rules.maximumMarketQuantity ||
          quantity <= 0) {
        _auditEvent(
          'scan_skip',
          'Calculated position size is below the exchange minimum for three protected target tranches.',
          symbol: idea.symbol,
        );
        return;
      }
""",
    """      if (quantity < rules.minimumQuantity ||
          quantity > rules.maximumMarketQuantity ||
          quantity <= 0) {
        _auditEvent(
          'scan_skip',
          'Calculated position size is below the exchange minimum for even one protected target.',
          symbol: idea.symbol,
        );
        return;
      }
""",
)
replace_once(
    service,
    """        if (quantity <
            rules.minimumQuantity / profitPlan.minimumTargetFraction) {
          await exchange.closePositionReduceOnly(
            position: position,
            clientId: '$clientId-small-close',
            credentials: credentials,
          );
          throw const LocalLiveTradeSafeException(
            'Filled quantity was too small for safe staged protection and was closed.',
          );
        }
""",
    """        if (quantity < rules.minimumQuantity) {
          await exchange.closePositionReduceOnly(
            position: position,
            clientId: '$clientId-small-close',
            credentials: credentials,
          );
          throw const LocalLiveTradeSafeException(
            'Filled quantity was too small for even one exchange-valid target and was closed.',
          );
        }
""",
)
replace_once(
    service,
    """        final allocation = ProfitProtectionAllocation.allocate(
          totalQuantity: quantity,
          plan: profitPlan,
          roundDown: rules.roundQuantityDown,
        );
        final targetQuantities = allocation.quantities;
        if (targetQuantities.any(
          (targetQuantity) => targetQuantity < rules.minimumQuantity,
        )) {
          await exchange.closePositionReduceOnly(
            position: position,
            clientId: '$clientId-invalid-ladder-close',
            credentials: credentials,
          );
          throw const LocalLiveTradeSafeException(
            'Filled quantity could not be split into three valid exchange targets and was closed.',
          );
        }
        final targetOrderIds = <String>[];
        try {
          for (var index = 0; index < 3; index++) {
            targetOrderIds.add(
              await exchange.placePartialTakeProfit(
                symbol: idea.symbol,
                positionId: position.positionId,
                triggerPrice: rules.roundPrice(idea.targets[index]),
                quantity: targetQuantities[index],
                credentials: credentials,
              ),
            );
          }
""",
    """        final allocation = ProfitProtectionAllocation.allocateAdaptive(
          totalQuantity: quantity,
          plan: profitPlan,
          minimumQuantity: rules.minimumQuantity,
          roundDown: rules.roundQuantityDown,
        );
        final targetQuantities = allocation.quantities;
        final effectiveAllocation = allocation.targetAllocation;
        if (!allocation.isValidFor(rules.minimumQuantity)) {
          await exchange.closePositionReduceOnly(
            position: position,
            clientId: '$clientId-invalid-ladder-close',
            credentials: credentials,
          );
          throw const LocalLiveTradeSafeException(
            'Filled quantity could not support even one complete exchange-valid target and was closed.',
          );
        }
        if (effectiveAllocation.activeTargetCount <
            configuration.targetAllocation.activeTargetCount) {
          _auditEvent(
            'target_allocation_adapted',
            'Target allocation automatically collapsed from '
                '${configuration.targetAllocation.activeTargetCount} to '
                '${effectiveAllocation.activeTargetCount} exchange-valid targets.',
            symbol: idea.symbol,
          );
        }
        final targetOrderIds = <String>['', '', ''];
        try {
          for (var index = 0; index < 3; index++) {
            if (targetQuantities[index] <= 0) continue;
            targetOrderIds[index] = await exchange.placePartialTakeProfit(
              symbol: idea.symbol,
              positionId: position.positionId,
              triggerPrice: rules.roundPrice(idea.targets[index]),
              quantity: targetQuantities[index],
              credentials: credentials,
            );
          }
""",
)
replace_once(
    service,
    """          targetAllocation: configuration.targetAllocation,
""",
    """          targetAllocation: effectiveAllocation,
""",
)
replace_once(
    service,
    """          'position_protected',
          'Entry fill, full stop and three staged targets confirmed '
              '(${(configuration.targetAllocation.tp1Fraction * 100).toStringAsFixed(0)}/'
              '${(configuration.targetAllocation.tp2Fraction * 100).toStringAsFixed(0)}/'
              '${(configuration.targetAllocation.tp3Fraction * 100).toStringAsFixed(0)}%; '
""",
    """          'position_protected',
          'Entry fill, full stop and ${effectiveAllocation.activeTargetCount} '
              'exchange-valid target(s) confirmed '
              '(${(effectiveAllocation.tp1Fraction * 100).toStringAsFixed(0)}/'
              '${(effectiveAllocation.tp2Fraction * 100).toStringAsFixed(0)}/'
              '${(effectiveAllocation.tp3Fraction * 100).toStringAsFixed(0)}%; '
""",
)
replace_once(
    service,
    """      if (managed.targetOrderIds.length != 3 ||
          managed.targetQuantities.length != 3 ||
          managed.targetOrderIds.any((item) => item.trim().isEmpty)) {
""",
    """      if (!_targetIdentityLayoutValid(
        targetOrderIds: managed.targetOrderIds,
        targetQuantities: managed.targetQuantities,
      )) {
""",
)
replace_once(
    service,
    """    if (targetOrderIds.length != 3 || targetQuantities.length != 3) {
      return false;
    }
    for (var index = 0; index < 3; index++) {
      final id = targetOrderIds[index].trim();
      if (id.isEmpty) return false;
      final matching = protection.where(
""",
    """    if (!_targetIdentityLayoutValid(
      targetOrderIds: targetOrderIds,
      targetQuantities: targetQuantities,
    )) {
      return false;
    }
    for (var index = 0; index < 3; index++) {
      final id = targetOrderIds[index].trim();
      final planned = targetQuantities[index];
      if (planned <= quantityTolerance) continue;
      final matching = protection.where(
""",
)
helper = """  bool _targetIdentityLayoutValid({
    required List<String> targetOrderIds,
    required List<double> targetQuantities,
  }) {
    if (targetOrderIds.length != 3 || targetQuantities.length != 3) {
      return false;
    }
    var inactiveSeen = false;
    for (var index = 0; index < 3; index++) {
      final quantity = targetQuantities[index];
      final id = targetOrderIds[index].trim();
      if (!quantity.isFinite || quantity < 0) return false;
      final active = quantity > 0;
      if (!active) {
        inactiveSeen = true;
        if (id.isNotEmpty) return false;
      } else {
        if (inactiveSeen || id.isEmpty) return false;
      }
    }
    return targetQuantities.first > 0;
  }

"""
if helper not in service.read_text():
    replace_once(service, "  bool _targetLadderConfirmed({\n", helper + "  bool _targetLadderConfirmed({\n")

orphan = ROOT / "lib/features/auto_trade/application/local_live_orphan_recovery.dart"
replace_once(
    orphan,
    """    if (stops.length != 1 || targets.length != 3) {
      return blocked('Exactly one stop and three targets are required.');
    }
""",
    """    if (stops.length != 1 || targets.isEmpty || targets.length > 3) {
      return blocked(
        'Exactly one stop and between one and three targets are required.',
      );
    }
""",
)
replace_once(
    orphan,
    """    if (targets.map((item) => item.orderId.trim()).toSet().length != 3) {
      return blocked('Target order identities are not unique.');
    }
""",
    """    if (targets.map((item) => item.orderId.trim()).toSet().length !=
        targets.length) {
      return blocked('Target order identities are not unique.');
    }
""",
)
replace_once(
    orphan,
    """      return blocked('The three target quantities do not cover the position.');
    }

    final allocation = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: targets[0].takeProfitQuantity / position.quantity,
      tp2Fraction: targets[1].takeProfitQuantity / position.quantity,
      tp3Fraction: targets[2].takeProfitQuantity / position.quantity,
    );
""",
    """      return blocked('The active target quantities do not cover the position.');
    }

    final paddedQuantities = <double>[
      ...targets.map((item) => item.takeProfitQuantity),
      ...List<double>.filled(3 - targets.length, 0),
    ];
    final paddedOrderIds = <String>[
      ...targets.map((item) => item.orderId.trim()),
      ...List<String>.filled(3 - targets.length, ''),
    ];
    final paddedTargetPrices = <double>[
      ...targets.map((item) => item.takeProfitPrice),
      ...List<double>.filled(3 - targets.length, 0),
    ];
    final allocation = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: paddedQuantities[0] / position.quantity,
      tp2Fraction: paddedQuantities[1] / position.quantity,
      tp3Fraction: paddedQuantities[2] / position.quantity,
    );
""",
)
replace_once(
    orphan,
    """      targets: List.unmodifiable(targets.map((item) => item.takeProfitPrice)),
""",
    """      targets: List.unmodifiable(paddedTargetPrices),
""",
)
replace_once(
    orphan,
    """      targetQuantities: List.unmodifiable(
        targets.map((item) => item.takeProfitQuantity),
      ),
      targetOrderIds: List.unmodifiable(
        targets.map((item) => item.orderId.trim()),
      ),
""",
    """      targetQuantities: List.unmodifiable(paddedQuantities),
      targetOrderIds: List.unmodifiable(paddedOrderIds),
""",
)

controller = ROOT / "lib/features/auto_trade/application/local_live_trade_controller.dart"
replace_once(
    controller,
    """          final affordability = LocalLiveEntryAffordability.calculate(
            availableMargin: account.available,
            markPrice: markPrice,
            minimumExchangeQuantity: rules.minimumQuantity,
            leverage: leverage,
          );
""",
    """          final affordability = LocalLiveEntryAffordability.calculate(
            availableMargin: account.available,
            markPrice: markPrice,
            minimumExchangeQuantity: rules.minimumQuantity,
            leverage: leverage,
            takeProfitTranches: 1,
          );
""",
)
replace_once(
    controller,
    """          '($lowestFloorSymbol, including three TP quantities and the safety '
          'buffer). Shortfall: $shortfall USDT. The actual risk and stop '
""",
    """          '($lowestFloorSymbol, including one exchange-valid TP quantity '
          'and the safety buffer). Shortfall: $shortfall USDT. The actual risk and stop '
""",
)

localizer = ROOT / "lib/core/localization/local_live_message_localizer.dart"
replace_once(
    localizer,
    """  static String localize(String message, {required bool persian}) {
""",
    """  static String localizeAudit({
    required String kind,
    required String message,
    required bool persian,
  }) {
    if (!persian) return message.trim().isEmpty ? kind : message;
    return switch (kind.trim()) {
      'stop' =>
        'ورودهای جدید با درخواست کاربر متوقف شدند؛ سفارش‌های محافظتی Bitunix فعال می‌مانند.',
      'pnl_projection_pending_empty_account' =>
        'حساب در این چرخه پوزیشن بازی نداشت؛ تکمیل تاریخچه سود و زیان در چرخه‌های بعدی ادامه پیدا می‌کند و این وضعیت خطا نیست.',
      'scan_skip' => localize(message, persian: true),
      'target_allocation_adapted' =>
        'حجم پوزیشن برای همه بخش‌های انتخابی کافی نبود؛ Quantara تعداد اهداف فعال را خودکار کاهش داد و کل حجم را میان سفارش‌های معتبر صرافی پوشش داد.',
      _ => localize(message, persian: true),
    };
  }

  static String localize(String message, {required bool persian}) {
""",
)
replace_once(
    localizer,
    """      'Calculated position size is below the exchange minimum for three protected target tranches.':
          'حجم محاسبه‌شده برای تقسیم ایمن بین سه حد سود، از حداقل صرافی کمتر است.',
""",
    """      'Calculated position size is below the exchange minimum for three protected target tranches.':
          'حجم محاسبه‌شده برای تقسیم ایمن بین سه حد سود، از حداقل صرافی کمتر است.',
      'Calculated position size is below the exchange minimum for even one protected target.':
          'حجم محاسبه‌شده حتی برای یک حد سود معتبر صرافی هم کمتر از حداقل مجاز است.',
      'Target allocation automatically collapsed from 3 to 2 exchange-valid targets.':
          'تقسیم حجم به‌صورت خودکار از سه هدف به دو هدف معتبر صرافی کاهش یافت.',
      'Target allocation automatically collapsed from 3 to 1 exchange-valid targets.':
          'تقسیم حجم به‌صورت خودکار از سه هدف به یک هدف معتبر صرافی کاهش یافت.',
""",
)
replace_once(
    localizer,
    r"""    r'^Available margin is ([0-9.]+) USDT\. The smallest exchange/margin floor among the selected symbols is about ([0-9.]+) USDT \(([^,]+), including three TP quantities and the safety buffer\)\. Shortfall: ([0-9.]+) USDT\. The actual risk and stop distance checks may require more capital\.$',
""",
    r"""    r'^Available margin is ([0-9.]+) USDT\. The smallest exchange/margin floor among the selected symbols is about ([0-9.]+) USDT \(([^,]+), including (?:three TP quantities|one exchange-valid TP quantity) and the safety buffer\)\. Shortfall: ([0-9.]+) USDT\. The actual risk and stop distance checks may require more capital\.$',
""",
)

auto_ui = ROOT / "lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart"
replace_once(
    auto_ui,
    """                      LocalLiveMessageLocalizer.localize(
                        event.message,
                        persian: _fa,
                      ),
""",
    """                      LocalLiveMessageLocalizer.localizeAudit(
                        kind: event.kind,
                        message: event.message,
                        persian: _fa,
                      ),
""",
)
replace_once(
    auto_ui,
    """                      'جمع سه هدف همیشه ۱۰۰٪ است. پس از تأیید کامل Fill هدف اول توسط Bitunix، استاپ باقیمانده فقط رو به سود و با احتساب هزینه‌ها منتقل می‌شود؛ کاهش صرف Quantity هیچ‌وقت محرک این تغییر نیست.',
                      'The three targets always total 100%. Only a complete Bitunix-confirmed TP1 fill may promote the remaining stop toward cost-aware profit; quantity reduction alone never triggers it.',
""",
    """                      'جمع اهداف فعال همیشه ۱۰۰٪ است. می‌توانی TP2 و TP3 را صفر کنی؛ اگر حجم یک هدف از حداقل Bitunix کمتر شود، Quantara آن بخش را خودکار با هدف قبلی ادغام می‌کند. فقط Fill تأییدشده TP1 می‌تواند استاپ باقی‌مانده را رو به سود جابه‌جا کند.',
                      'Active targets always total 100%. TP2 and TP3 may be zero; when a target quantity is below the Bitunix minimum, Quantara automatically merges it into the previous target. Only a confirmed TP1 fill may promote the remaining stop toward profit.',
""",
)

test = ROOT / "test/adaptive_tp_allocation_test.dart"
test.write_text(r"""import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/remaining_target_protection_policy.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  double tenthDown(double value) => (value * 10).floor() / 10;

  ProfitProtectionPlan plan(ProfitProtectionTargetAllocation allocation) =>
      ProfitProtectionPlan(
        profile: ProfitProtectionProfile.transitionBalance,
        targetAllocation: allocation,
      );

  test('manual one and two target allocations are valid and contiguous', () {
    final one = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 1,
      tp2Fraction: 0,
      tp3Fraction: 0,
    );
    final two = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.8,
      tp2Fraction: 0.2,
      tp3Fraction: 0,
    );
    expect(one.activeTargetCount, 1);
    expect(two.activeTargetCount, 2);
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.8,
        tp2Fraction: 0,
        tp3Fraction: 0.2,
      ),
      throwsFormatException,
    );
  });

  test('adaptive allocation collapses an undersized TP3 into TP2', () {
    final configured = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.8,
      tp2Fraction: 0.15,
      tp3Fraction: 0.05,
    );
    final result = ProfitProtectionAllocation.allocateAdaptive(
      totalQuantity: 10,
      plan: plan(configured),
      minimumQuantity: 1,
      roundDown: tenthDown,
    );
    expect(result.activeTargetCount, 2);
    expect(result.targetAllocation.fractions, [0.8, 0.2, 0]);
    expect(result.quantities, [8, 2, 0]);
    expect(result.isValidFor(1), isTrue);
  });

  test('adaptive allocation collapses to one fully covered target', () {
    final configured = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.8,
      tp2Fraction: 0.15,
      tp3Fraction: 0.05,
    );
    final result = ProfitProtectionAllocation.allocateAdaptive(
      totalQuantity: 1.5,
      plan: plan(configured),
      minimumQuantity: 1,
      roundDown: tenthDown,
    );
    expect(result.activeTargetCount, 1);
    expect(result.targetAllocation.fractions, [1, 0, 0]);
    expect(result.quantities, [1.5, 0, 0]);
    expect(result.isValidFor(1), isTrue);
  });

  test('inactive target slots need zero quantity and empty order identity', () {
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: const ['tp-1', '', ''],
        targetQuantities: const [1.5, 0, 0],
        filledQuantities: const [0, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-1',
            triggerPrice: 110,
            quantity: 1.5,
          ),
        ],
        quantityTolerance: 0.01,
      ),
      isTrue,
    );
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: const ['tp-1', 'unexpected', ''],
        targetQuantities: const [1.5, 0, 0],
        filledQuantities: const [0, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-1',
            triggerPrice: 110,
            quantity: 1.5,
          ),
        ],
        quantityTolerance: 0.01,
      ),
      isFalse,
    );
  });
}
""")

source_test = ROOT / "test/adaptive_tp_source_test.dart"
source_test.write_text(r"""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Local Live places only active target orders and persists inactive slots', () {
    final service = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(service, contains('ProfitProtectionAllocation.allocateAdaptive'));
    expect(service, contains("final targetOrderIds = <String>['', '', ''];"));
    expect(service, contains('if (targetQuantities[index] <= 0) continue;'));
    expect(service, contains('targetAllocation: effectiveAllocation'));
    expect(service, isNot(contains('minimumQuantity / profitPlan.minimumTargetFraction')));
  });

  test('audit UI localizes normal status kinds instead of generic errors', () {
    final ui = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    final localizer = File(
      'lib/core/localization/local_live_message_localizer.dart',
    ).readAsStringSync();
    expect(ui, contains('LocalLiveMessageLocalizer.localizeAudit'));
    expect(localizer, contains("'pnl_projection_pending_empty_account'"));
    expect(localizer, contains("'target_allocation_adapted'"));
  });

  test('orphan recovery accepts one to three targets and pads inactive slots', () {
    final recovery = File(
      'lib/features/auto_trade/application/local_live_orphan_recovery.dart',
    ).readAsStringSync();
    expect(recovery, contains('targets.isEmpty || targets.length > 3'));
    expect(recovery, contains('paddedQuantities'));
    expect(recovery, contains("List<String>.filled(3 - targets.length, '')"));
  });
}
""")

print("issue 167 adaptive target patch applied")
