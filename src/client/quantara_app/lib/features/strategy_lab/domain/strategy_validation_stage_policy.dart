import 'strategy_promotion_models.dart';

enum StrategyValidationStage {
  deterministicReplay,
  realtimeShadow,
  paper,
  tinyRiskCanary,
  promotionEligible,
}

enum StrategyValidationStageBlock {
  incompleteEvidence,
  replayNotPassed,
  shadowNotPassed,
  paperNotPassed,
  systemStartDisabled,
  capitalGuardianBlocked,
  featureFlagDisabled,
  driftDowngradeActive,
}

final class StrategyValidationStageDecision {
  const StrategyValidationStageDecision({
    required this.stage,
    required this.allowed,
    required this.blocks,
  });

  final StrategyValidationStage stage;
  final bool allowed;
  final List<StrategyValidationStageBlock> blocks;
}

abstract final class StrategyValidationStagePolicy {
  static StrategyValidationStageDecision evaluate({
    required StrategyValidationStage requestedStage,
    required StrategyPromotionPacket packet,
    required bool replayPassed,
    required bool shadowPassed,
    required bool paperPassed,
    required bool systemStartEnabled,
    required bool capitalGuardianAllowsNewRisk,
  }) {
    final blocks = <StrategyValidationStageBlock>[];
    if (!packet.reproducible) {
      blocks.add(StrategyValidationStageBlock.incompleteEvidence);
    }
    if (!packet.featureFlagEnabled) {
      blocks.add(StrategyValidationStageBlock.featureFlagDisabled);
    }
    if (packet.downgradeReasons.isNotEmpty &&
        requestedStage.index >= StrategyValidationStage.tinyRiskCanary.index) {
      blocks.add(StrategyValidationStageBlock.driftDowngradeActive);
    }
    if (requestedStage.index >= StrategyValidationStage.realtimeShadow.index &&
        !replayPassed) {
      blocks.add(StrategyValidationStageBlock.replayNotPassed);
    }
    if (requestedStage.index >= StrategyValidationStage.paper.index &&
        !shadowPassed) {
      blocks.add(StrategyValidationStageBlock.shadowNotPassed);
    }
    if (requestedStage.index >= StrategyValidationStage.tinyRiskCanary.index &&
        !paperPassed) {
      blocks.add(StrategyValidationStageBlock.paperNotPassed);
    }
    if (requestedStage.index >= StrategyValidationStage.tinyRiskCanary.index &&
        !systemStartEnabled) {
      blocks.add(StrategyValidationStageBlock.systemStartDisabled);
    }
    if (requestedStage.index >= StrategyValidationStage.tinyRiskCanary.index &&
        !capitalGuardianAllowsNewRisk) {
      blocks.add(StrategyValidationStageBlock.capitalGuardianBlocked);
    }
    if (requestedStage == StrategyValidationStage.promotionEligible &&
        !packet.promotionEvidenceComplete) {
      blocks.add(StrategyValidationStageBlock.incompleteEvidence);
    }

    return StrategyValidationStageDecision(
      stage: requestedStage,
      allowed: blocks.isEmpty,
      blocks: List.unmodifiable(blocks.toSet()),
    );
  }
}
