import 'dart:collection';

import 'market_chart_models.dart';
import 'market_regime_models.dart';

enum ContextualEvidenceFamily { structure, zone, candle, volume, momentum }

enum StructureEvent { none, breakOfStructure, changeOfCharacter, failedBreak }

enum SwingSequence { unknown, bullish, bearish, mixed }

enum ExpectedMarketMove {
  continuationHigher,
  continuationLower,
  rangeRotationHigher,
  rangeRotationLower,
  breakoutContinuation,
  failedBreakReversal,
  observeOnly,
}

final class EvidenceFamilyScore {
  EvidenceFamilyScore({
    required this.family,
    required this.rawScore,
    required this.cap,
    required Iterable<String> reasons,
  }) : cappedScore = rawScore.clamp(0, cap).toDouble(),
       reasons = UnmodifiableListView(reasons.toList(growable: false)) {
    if (!rawScore.isFinite || !cap.isFinite || cap <= 0) {
      throw ArgumentError('Evidence score and cap must be finite and valid.');
    }
  }

  final ContextualEvidenceFamily family;
  final double rawScore;
  final double cap;
  final double cappedScore;
  final UnmodifiableListView<String> reasons;
}

final class StructureExpectationAssessment {
  StructureExpectationAssessment({
    required this.sequence,
    required this.event,
    required this.bias,
    required this.regime,
    required this.expectedMove,
    required this.protectedSwing,
    required this.score,
    required Iterable<String> reasons,
  }) : reasons = UnmodifiableListView(reasons.toList(growable: false));

  final SwingSequence sequence;
  final StructureEvent event;
  final ChartDirection bias;
  final MarketRegime regime;
  final ExpectedMarketMove expectedMove;
  final double? protectedSwing;
  final double score;
  final UnmodifiableListView<String> reasons;
}

final class ZoneQualityAssessment {
  ZoneQualityAssessment({
    required this.zone,
    required this.freshness,
    required this.departureStrength,
    required this.touchQuality,
    required this.penetrationQuality,
    required this.compressionQuality,
    required this.roomToTarget,
    required this.score,
    required Iterable<String> reasons,
  }) : reasons = UnmodifiableListView(reasons.toList(growable: false));

  final ChartPriceZone? zone;
  final double freshness;
  final double departureStrength;
  final double touchQuality;
  final double penetrationQuality;
  final double compressionQuality;
  final double roomToTarget;
  final double score;
  final UnmodifiableListView<String> reasons;
}

final class CandleBehaviorAssessment {
  CandleBehaviorAssessment({
    required this.closeLocation,
    required this.bodyFraction,
    required this.rejectionStrength,
    required this.engulfing,
    required this.reclaim,
    required this.acceptance,
    required this.absorption,
    required this.followThrough,
    required this.failedBreakout,
    required this.score,
    required Iterable<String> reasons,
  }) : reasons = UnmodifiableListView(reasons.toList(growable: false));

  final double closeLocation;
  final double bodyFraction;
  final double rejectionStrength;
  final bool engulfing;
  final bool reclaim;
  final bool acceptance;
  final bool absorption;
  final bool followThrough;
  final bool failedBreakout;
  final double score;
  final UnmodifiableListView<String> reasons;
}

final class VolumeBehaviorAssessment {
  VolumeBehaviorAssessment({
    required this.relativeVolume,
    required this.breakoutExpansion,
    required this.pullbackContraction,
    required this.reExpansion,
    required this.climax,
    required this.absorption,
    required this.effortVsResult,
    required this.divergence,
    required this.score,
    required Iterable<String> reasons,
  }) : reasons = UnmodifiableListView(reasons.toList(growable: false));

  final double relativeVolume;
  final bool breakoutExpansion;
  final bool pullbackContraction;
  final bool reExpansion;
  final bool climax;
  final bool absorption;
  final bool effortVsResult;
  final bool divergence;
  final double score;
  final UnmodifiableListView<String> reasons;
}

final class MomentumContextAssessment {
  MomentumContextAssessment({
    required this.rsi,
    required this.adx,
    required this.directionalSpread,
    required this.rsiReset,
    required this.divergence,
    required this.momentumLoss,
    required this.expansion,
    required this.score,
    required Iterable<String> reasons,
  }) : reasons = UnmodifiableListView(reasons.toList(growable: false));

  final double rsi;
  final double adx;
  final double directionalSpread;
  final bool rsiReset;
  final bool divergence;
  final bool momentumLoss;
  final bool expansion;
  final double score;
  final UnmodifiableListView<String> reasons;
}

final class ContextualPriceActionAssessment {
  ContextualPriceActionAssessment({
    required this.version,
    required this.structure,
    required this.zone,
    required this.candle,
    required this.volume,
    required this.momentum,
    required Map<ContextualEvidenceFamily, EvidenceFamilyScore> families,
    required this.setupQualityScore,
    required this.regime,
    required this.expectation,
    required this.trigger,
    required this.invalidation,
  }) : families = UnmodifiableMapView(Map.of(families)) {
    if (version.trim().isEmpty ||
        setupQualityScore < 0 ||
        setupQualityScore > 100 ||
        expectation.trim().isEmpty ||
        trigger.trim().isEmpty ||
        invalidation.trim().isEmpty) {
      throw ArgumentError('Contextual assessment is incomplete.');
    }
    if (this.families.length != ContextualEvidenceFamily.values.length ||
        !ContextualEvidenceFamily.values.every(this.families.containsKey)) {
      throw ArgumentError('Every evidence family must be represented.');
    }
  }

  final String version;
  final StructureExpectationAssessment structure;
  final ZoneQualityAssessment zone;
  final CandleBehaviorAssessment candle;
  final VolumeBehaviorAssessment volume;
  final MomentumContextAssessment momentum;
  final UnmodifiableMapView<ContextualEvidenceFamily, EvidenceFamilyScore>
  families;
  final int setupQualityScore;
  final MarketRegime regime;
  final String expectation;
  final String trigger;
  final String invalidation;

  Map<String, double> get scoreBreakdown => Map.unmodifiable({
    for (final entry in families.entries)
      entry.key.name: entry.value.cappedScore,
  });

  List<String> get evidenceReasons => List.unmodifiable([
    for (final family in ContextualEvidenceFamily.values)
      ...families[family]!.reasons,
  ]);
}
