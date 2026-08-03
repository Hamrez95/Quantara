import '../../market_analysis/domain/market_regime_models.dart';
import 'owner_alpha_models.dart';

enum ProfitProtectionProfile {
  rangeDefense,
  trendBalance,
  breakoutRunner,
  transitionBalance,
  disorderDefense,
}

final class ProfitProtectionTargetAllocation {
  const ProfitProtectionTargetAllocation._({
    required this.tp1Fraction,
    required this.tp2Fraction,
    required this.tp3Fraction,
  });

  static const standard = ProfitProtectionTargetAllocation._(
    tp1Fraction: 0.65,
    tp2Fraction: 0.20,
    tp3Fraction: 0.15,
  );

  final double tp1Fraction;
  final double tp2Fraction;
  final double tp3Fraction;

  List<double> get fractions =>
      List.unmodifiable([tp1Fraction, tp2Fraction, tp3Fraction]);

  double get minimumFraction => [
    tp1Fraction,
    tp2Fraction,
    tp3Fraction,
  ].reduce((left, right) => left < right ? left : right);

  factory ProfitProtectionTargetAllocation.checked({
    required double tp1Fraction,
    required double tp2Fraction,
    required double tp3Fraction,
  }) {
    final values = [tp1Fraction, tp2Fraction, tp3Fraction];
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (values.any((value) => !value.isFinite || value <= 0) ||
        (total - 1).abs() > 0.000001) {
      throw const FormatException(
        'TP1, TP2 and TP3 must be positive and total exactly 100%.',
      );
    }
    return ProfitProtectionTargetAllocation._(
      tp1Fraction: tp1Fraction,
      tp2Fraction: tp2Fraction,
      tp3Fraction: tp3Fraction,
    );
  }

  factory ProfitProtectionTargetAllocation.fromFractions(
    Iterable<double> fractions, {
    ProfitProtectionTargetAllocation fallback = standard,
  }) {
    final values = fractions.toList(growable: false);
    if (values.length != 3) return fallback;
    try {
      return ProfitProtectionTargetAllocation.checked(
        tp1Fraction: values[0],
        tp2Fraction: values[1],
        tp3Fraction: values[2],
      );
    } on FormatException {
      return fallback;
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'tp1Fraction': tp1Fraction,
    'tp2Fraction': tp2Fraction,
    'tp3Fraction': tp3Fraction,
  };

  factory ProfitProtectionTargetAllocation.fromJson(Object? value) {
    if (value is Map<Object?, Object?>) {
      final normalized = value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
      return ProfitProtectionTargetAllocation.fromFractions([
        (normalized['tp1Fraction'] as num?)?.toDouble() ?? double.nan,
        (normalized['tp2Fraction'] as num?)?.toDouble() ?? double.nan,
        (normalized['tp3Fraction'] as num?)?.toDouble() ?? double.nan,
      ]);
    }
    if (value is List<Object?>) {
      return ProfitProtectionTargetAllocation.fromFractions(
        value.whereType<num>().map((item) => item.toDouble()),
      );
    }
    return standard;
  }

  @override
  bool operator ==(Object other) =>
      other is ProfitProtectionTargetAllocation &&
      other.tp1Fraction == tp1Fraction &&
      other.tp2Fraction == tp2Fraction &&
      other.tp3Fraction == tp3Fraction;

  @override
  int get hashCode => Object.hash(tp1Fraction, tp2Fraction, tp3Fraction);
}

final class ProfitProtectionPlan {
  const ProfitProtectionPlan({
    required this.profile,
    required this.targetAllocation,
    this.costBufferRate = 0.0017,
  });

  final ProfitProtectionProfile profile;
  final ProfitProtectionTargetAllocation targetAllocation;
  final double costBufferRate;

  List<double> get targetFractions => targetAllocation.fractions;

  double get minimumTargetFraction => targetAllocation.minimumFraction;

  double get tp1RemainingTrigger =>
      (1 - targetAllocation.tp1Fraction + 0.02).clamp(0, 1).toDouble();

  double get tp2RemainingTrigger =>
      (targetAllocation.tp3Fraction + 0.02).clamp(0, 1).toDouble();

  ProfitProtectionPlan withTargetAllocation(
    ProfitProtectionTargetAllocation allocation,
  ) => ProfitProtectionPlan(
    profile: profile,
    targetAllocation: allocation,
    costBufferRate: costBufferRate,
  );
}

final class ProfitProtectionAllocation {
  const ProfitProtectionAllocation({
    required this.totalQuantity,
    required this.quantities,
  });

  final double totalQuantity;
  final List<double> quantities;

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

  bool isValidFor(double minimumQuantity) =>
      totalQuantity > 0 &&
      quantities.length == 3 &&
      quantities.every(
        (quantity) => quantity.isFinite && quantity >= minimumQuantity,
      ) &&
      residualQuantity >= -0.000000001;

  static ProfitProtectionAllocation allocate({
    required double totalQuantity,
    required ProfitProtectionPlan plan,
    required double Function(double value) roundDown,
  }) {
    // Later targets are rounded down first. Only the deterministic exchange
    // step remainder is assigned to TP1 so the total never exceeds exposure.
    final tp2 = roundDown(totalQuantity * plan.targetAllocation.tp2Fraction);
    final tp3 = roundDown(totalQuantity * plan.targetAllocation.tp3Fraction);
    final tp1 = roundDown(totalQuantity - tp2 - tp3);
    return ProfitProtectionAllocation(
      totalQuantity: totalQuantity,
      quantities: List.unmodifiable([tp1, tp2, tp3]),
    );
  }
}

abstract final class ProfitProtectionPolicy {
  static const _range = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.rangeDefense,
    targetAllocation: ProfitProtectionTargetAllocation._(
      tp1Fraction: 0.50,
      tp2Fraction: 0.25,
      tp3Fraction: 0.25,
    ),
  );
  static const _trend = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.trendBalance,
    targetAllocation: ProfitProtectionTargetAllocation._(
      tp1Fraction: 0.45,
      tp2Fraction: 0.30,
      tp3Fraction: 0.25,
    ),
  );
  static const _breakout = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.breakoutRunner,
    targetAllocation: ProfitProtectionTargetAllocation._(
      tp1Fraction: 0.40,
      tp2Fraction: 0.25,
      tp3Fraction: 0.35,
    ),
  );
  static const _transition = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.transitionBalance,
    targetAllocation: ProfitProtectionTargetAllocation._(
      tp1Fraction: 0.40,
      tp2Fraction: 0.30,
      tp3Fraction: 0.30,
    ),
  );
  static const _disorder = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.disorderDefense,
    targetAllocation: ProfitProtectionTargetAllocation._(
      tp1Fraction: 0.50,
      tp2Fraction: 0.25,
      tp3Fraction: 0.25,
    ),
  );

  static ProfitProtectionPlan forRegime(MarketRegime regime) =>
      switch (regime) {
        MarketRegime.range => _range,
        MarketRegime.directionalTrend => _trend,
        MarketRegime.breakoutExpansion => _breakout,
        MarketRegime.transition => _transition,
        MarketRegime.disorder => _disorder,
      };

  static ProfitProtectionPlan forIdea(
    TradeIdea idea, {
    ProfitProtectionTargetAllocation? targetAllocation,
  }) {
    final base = forRegime(idea.marketRegime);
    return targetAllocation == null
        ? base
        : base.withTargetAllocation(targetAllocation);
  }

  static ProfitProtectionPlan forJournal(SignalJournalEntry entry) =>
      forRegime(entry.marketRegime);
}
