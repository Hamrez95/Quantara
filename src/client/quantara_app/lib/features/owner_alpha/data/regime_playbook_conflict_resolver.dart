import '../domain/regime_playbook_models.dart';

final class PlaybookConflictResolution {
  const PlaybookConflictResolution({
    required this.outcome,
    required this.selected,
  });

  final PlaybookConflictOutcome outcome;
  final RegimePlaybookEvaluation? selected;
}

abstract final class RegimePlaybookConflictResolver {
  static PlaybookConflictResolution resolve(
    Iterable<RegimePlaybookEvaluation> evaluations, {
    int minimumQualityAdvantage = 10,
  }) {
    if (minimumQualityAdvantage < 1 || minimumQualityAdvantage > 50) {
      throw ArgumentError.value(
        minimumQualityAdvantage,
        'minimumQualityAdvantage',
      );
    }
    final armed = evaluations.where((item) => item.isArmed).toList()
      ..sort((left, right) {
        final quality = right.qualityScore.compareTo(left.qualityScore);
        return quality != 0
            ? quality
            : left.playbook.name.compareTo(right.playbook.name);
      });
    if (armed.isEmpty) {
      return const PlaybookConflictResolution(
        outcome: PlaybookConflictOutcome.none,
        selected: null,
      );
    }
    final directions = armed.map((item) => item.direction).toSet();
    if (directions.length <= 1) {
      return PlaybookConflictResolution(
        outcome: PlaybookConflictOutcome.none,
        selected: armed.first,
      );
    }
    final top = armed.first;
    final runnerUp = armed[1];
    if (top.qualityScore - runnerUp.qualityScore >= minimumQualityAdvantage) {
      return PlaybookConflictResolution(
        outcome: PlaybookConflictOutcome.selectedHighestQuality,
        selected: top,
      );
    }
    return const PlaybookConflictResolution(
      outcome: PlaybookConflictOutcome.ambiguousOpposingSignals,
      selected: null,
    );
  }
}
