import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/dow_structure_models.dart';

void main() {
  test('Dow rollout is disabled and non-authoritative by default', () {
    const rollout = DowStructureRollout.disabled();

    expect(rollout.enabled, isFalse);
    expect(rollout.mayRejectNewCandidate, isFalse);
    expect(rollout.config.scoreCap, 20);
    expect(rollout.config.version, 'dow-structure/1.0');
  });

  test('shadow cannot reject candidates', () {
    const rollout = DowStructureRollout.shadow();

    expect(rollout.enabled, isTrue);
    expect(rollout.mayRejectNewCandidate, isFalse);
  });
}
