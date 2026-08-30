import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/portfolio_risk/domain/dynamic_risk_budget.dart';

void main() {
  const fullCaps = RiskBudgetCaps(
    dailyRemaining: 1000,
    weeklyRemaining: 1000,
    sessionRemaining: 1000,
    strategyRemaining: 1000,
    portfolioRemaining: 1000,
  );

  test(
    'riskPercent is dimensionless and riskAmount equals equity times it',
    () {
      final decision = DynamicRiskBudgetPolicy.evaluate(
        equity: 10000,
        baseRiskPercent: 0.01,
        multipliers: const DynamicRiskMultipliers(
          capitalRegime: 0.8,
          volatility: 0.5,
          drawdown: 0.5,
          execution: 0.5,
        ),
        caps: fullCaps,
      );

      expect(decision.riskPercent, closeTo(0.001, 1e-12));
      expect(decision.unconstrainedRiskAmount, closeTo(10, 1e-9));
      expect(decision.allowedRiskAmount, closeTo(10, 1e-9));
      expect(decision.bindingBudget, RiskBudgetBinding.dynamicSizing);
    },
  );

  test('allowed risk is the strict minimum across every budget and cap', () {
    final decision = DynamicRiskBudgetPolicy.evaluate(
      equity: 10000,
      baseRiskPercent: 0.02,
      multipliers: const DynamicRiskMultipliers(
        capitalRegime: 1,
        volatility: 1,
        drawdown: 1,
        execution: 1,
      ),
      caps: const RiskBudgetCaps(
        dailyRemaining: 150,
        weeklyRemaining: 140,
        sessionRemaining: 130,
        strategyRemaining: 40,
        portfolioRemaining: 120,
      ),
    );

    expect(decision.unconstrainedRiskAmount, 200);
    expect(decision.allowedRiskAmount, 40);
    expect(decision.bindingBudget, RiskBudgetBinding.strategy);
  });

  test('zero remaining cap blocks new risk immediately', () {
    final decision = DynamicRiskBudgetPolicy.evaluate(
      equity: 10000,
      baseRiskPercent: 0.01,
      multipliers: const DynamicRiskMultipliers(
        capitalRegime: 1,
        volatility: 1,
        drawdown: 1,
        execution: 1,
      ),
      caps: const RiskBudgetCaps(
        dailyRemaining: 100,
        weeklyRemaining: 100,
        sessionRemaining: 0,
        strategyRemaining: 100,
        portfolioRemaining: 100,
      ),
    );

    expect(decision.allowedRiskAmount, 0);
    expect(decision.bindingBudget, RiskBudgetBinding.session);
    expect(decision.blocked, isTrue);
  });

  test(
    'multipliers may reduce but cannot amplify the configured base risk',
    () {
      expect(
        () => DynamicRiskBudgetPolicy.evaluate(
          equity: 10000,
          baseRiskPercent: 0.01,
          multipliers: const DynamicRiskMultipliers(
            capitalRegime: 1.01,
            volatility: 1,
            drawdown: 1,
            execution: 1,
          ),
          caps: fullCaps,
        ),
        throwsFormatException,
      );
    },
  );

  test('invalid negative or non-finite caps fail closed', () {
    expect(
      () => DynamicRiskBudgetPolicy.evaluate(
        equity: 10000,
        baseRiskPercent: 0.01,
        multipliers: const DynamicRiskMultipliers(
          capitalRegime: 1,
          volatility: 1,
          drawdown: 1,
          execution: 1,
        ),
        caps: const RiskBudgetCaps(
          dailyRemaining: 100,
          weeklyRemaining: 100,
          sessionRemaining: 100,
          strategyRemaining: -1,
          portfolioRemaining: 100,
        ),
      ),
      throwsFormatException,
    );
  });

  test('base risk percent rejects percentage-like values above one', () {
    expect(
      () => DynamicRiskBudgetPolicy.evaluate(
        equity: 10000,
        baseRiskPercent: 2,
        multipliers: const DynamicRiskMultipliers(
          capitalRegime: 1,
          volatility: 1,
          drawdown: 1,
          execution: 1,
        ),
        caps: fullCaps,
      ),
      throwsFormatException,
    );
  });
}
