import 'dart:math' as math;

import 'package:flutter/foundation.dart';

@immutable
final class DynamicRiskMultipliers {
  const DynamicRiskMultipliers({
    required this.capitalRegime,
    required this.volatility,
    required this.drawdown,
    required this.execution,
  });

  final double capitalRegime;
  final double volatility;
  final double drawdown;
  final double execution;

  void validate() {
    for (final value in [capitalRegime, volatility, drawdown, execution]) {
      if (!value.isFinite || value < 0 || value > 1) {
        throw const FormatException(
          'Dynamic risk multipliers must be finite and within [0, 1].',
        );
      }
    }
  }

  double get combined {
    validate();
    return capitalRegime * volatility * drawdown * execution;
  }
}

@immutable
final class RiskBudgetCaps {
  const RiskBudgetCaps({
    required this.dailyRemaining,
    required this.weeklyRemaining,
    required this.sessionRemaining,
    required this.strategyRemaining,
    required this.portfolioRemaining,
  });

  final double dailyRemaining;
  final double weeklyRemaining;
  final double sessionRemaining;
  final double strategyRemaining;
  final double portfolioRemaining;

  void validate() {
    for (final value in [
      dailyRemaining,
      weeklyRemaining,
      sessionRemaining,
      strategyRemaining,
      portfolioRemaining,
    ]) {
      if (!value.isFinite || value < 0) {
        throw const FormatException(
          'Risk budget caps must be finite and non-negative.',
        );
      }
    }
  }

  double get strictRemaining {
    validate();
    return [
      dailyRemaining,
      weeklyRemaining,
      sessionRemaining,
      strategyRemaining,
      portfolioRemaining,
    ].reduce(math.min);
  }
}

@immutable
final class DynamicRiskBudgetDecision {
  const DynamicRiskBudgetDecision({
    required this.riskPercent,
    required this.unconstrainedRiskAmount,
    required this.allowedRiskAmount,
    required this.bindingBudget,
  });

  /// Dimensionless fraction of equity, e.g. 0.005 means 0.5%.
  final double riskPercent;
  final double unconstrainedRiskAmount;
  final double allowedRiskAmount;
  final RiskBudgetBinding bindingBudget;

  bool get blocked => allowedRiskAmount <= 1e-9;
}

enum RiskBudgetBinding {
  dynamicSizing,
  daily,
  weekly,
  session,
  strategy,
  portfolio,
}

abstract final class DynamicRiskBudgetPolicy {
  static DynamicRiskBudgetDecision evaluate({
    required double equity,
    required double baseRiskPercent,
    required DynamicRiskMultipliers multipliers,
    required RiskBudgetCaps caps,
  }) {
    if (!equity.isFinite || equity <= 0) {
      throw const FormatException('Equity must be finite and positive.');
    }
    if (!baseRiskPercent.isFinite ||
        baseRiskPercent < 0 ||
        baseRiskPercent > 1) {
      throw const FormatException(
        'Base risk percent must be a dimensionless value within [0, 1].',
      );
    }
    multipliers.validate();
    caps.validate();

    final riskPercent = baseRiskPercent * multipliers.combined;
    final unconstrainedRiskAmount = equity * riskPercent;
    final constraints = <(RiskBudgetBinding, double)>[
      (RiskBudgetBinding.dynamicSizing, unconstrainedRiskAmount),
      (RiskBudgetBinding.daily, caps.dailyRemaining),
      (RiskBudgetBinding.weekly, caps.weeklyRemaining),
      (RiskBudgetBinding.session, caps.sessionRemaining),
      (RiskBudgetBinding.strategy, caps.strategyRemaining),
      (RiskBudgetBinding.portfolio, caps.portfolioRemaining),
    ];

    var binding = constraints.first;
    for (final candidate in constraints.skip(1)) {
      if (candidate.$2 < binding.$2) binding = candidate;
    }

    return DynamicRiskBudgetDecision(
      riskPercent: riskPercent,
      unconstrainedRiskAmount: unconstrainedRiskAmount,
      allowedRiskAmount: binding.$2,
      bindingBudget: binding.$1,
    );
  }
}
