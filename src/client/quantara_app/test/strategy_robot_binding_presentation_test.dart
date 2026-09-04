import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_robot_binding.dart';
import 'package:quantara_app/features/owner_alpha/presentation/strategy_robot_binding_presentation.dart';

void main() {
  const binding = StrategyRobotBinding(
    evaluationRunId: 'evaluation-43',
    setupId: 'setup-43',
    strategyId: 'structure_zones',
    strategyVersion: '12.0.0',
    parameterSchemaVersion: 3,
    normalizedParameters: <String, Object?>{'cadence': 'balanced'},
    snapshotHash: 'ab12cd34ef56',
    managementPolicyVersion: 'structure-zones-management/12.0',
    implementationVersion: 'professional-strategy-engine/12.0',
    symbol: 'BTCUSDT',
    timeframe: '15m',
  );

  test('confirmation summary exposes exact evaluated identity', () {
    final presentation = StrategyRobotBindingPresentation.fromBinding(binding);

    expect(presentation.shortHash, 'ab12cd34…');
    expect(
      presentation.confirmationSummary(persian: false),
      'structure_zones v12.0.0 • hash ab12cd34… • BTCUSDT/15m • evaluation evaluation-43',
    );
    expect(
      presentation.robotStatus(persian: false),
      'Robot: structure_zones v12.0.0 — exact evaluation evaluation-43 snapshot',
    );
    expect(presentation.useInRobotLabel(persian: false), 'Use in Robot');
  });

  test('Persian copy preserves the same immutable identity', () {
    final presentation = StrategyRobotBindingPresentation.fromBinding(binding);

    expect(
      presentation.confirmationSummary(persian: true),
      'structure_zones v12.0.0 • هش ab12cd34… • BTCUSDT/15m • ارزیابی evaluation-43',
    );
    expect(
      presentation.robotStatus(persian: true),
      'ربات: structure_zones v12.0.0 — همان نسخه ارزیابی evaluation-43',
    );
    expect(presentation.useInRobotLabel(persian: true), 'استفاده در ربات');
  });

  test('short hashes are never padded or rewritten', () {
    const shortBinding = StrategyRobotBinding(
      evaluationRunId: 'evaluation-1',
      setupId: 'setup-1',
      strategyId: 'strategy',
      strategyVersion: '1.0.0',
      parameterSchemaVersion: 1,
      normalizedParameters: <String, Object?>{},
      snapshotHash: 'abc123',
      managementPolicyVersion: 'management/1',
      implementationVersion: 'implementation/1',
      symbol: 'ETHUSDT',
      timeframe: '1h',
    );

    final presentation = StrategyRobotBindingPresentation.fromBinding(
      shortBinding,
    );
    expect(presentation.shortHash, 'abc123');
  });
}
