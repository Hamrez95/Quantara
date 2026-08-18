import '../../market_analysis/domain/market_regime_models.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/realtime_candidate_models.dart';

enum RealtimeRadarLane { forming, armed, triggered, managing, missed }

/// Bounded, read-only projection of realtime domain evidence for the Radar UI.
///
/// No execution or risk decision is inferred here. Journal outcomes may only
/// advance a triggered candidate to Managing or a terminal Missed state.
final class RealtimeRadarItemPresentation {
  const RealtimeRadarItemPresentation._({
    required this.candidate,
    required this.lane,
    required this.dataUncertain,
    required this.age,
    required this.distanceToEntryPercent,
    required this.rawReasonCode,
    required this.regime,
  });

  factory RealtimeRadarItemPresentation.fromEvidence({
    required RealtimeOpportunityCandidate candidate,
    required DateTime nowUtc,
    required bool realtimeOperational,
    SignalJournalEntry? journalEntry,
  }) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'UTC is required.');
    }
    final outcome = journalEntry?.outcome;
    final lane = switch (outcome) {
      SignalOutcome.tp1 || SignalOutcome.tp2 => RealtimeRadarLane.managing,
      SignalOutcome.expiredUntriggered => RealtimeRadarLane.missed,
      SignalOutcome.active => RealtimeRadarLane.triggered,
      _ => switch (candidate.stage) {
        OpportunityStage.detected ||
        OpportunityStage.forming => RealtimeRadarLane.forming,
        OpportunityStage.armed => RealtimeRadarLane.armed,
        OpportunityStage.triggered => RealtimeRadarLane.triggered,
        OpportunityStage.missed ||
        OpportunityStage.expired ||
        OpportunityStage.invalidated => RealtimeRadarLane.missed,
      },
    };
    final age = nowUtc.difference(candidate.lastUpdatedAtUtc);
    final observedPrice = candidate.lastPrice;
    return RealtimeRadarItemPresentation._(
      candidate: candidate,
      lane: lane,
      dataUncertain:
          !realtimeOperational ||
          candidate.transitionReason == OpportunityTransitionReason.dataStale,
      age: age.isNegative ? Duration.zero : age,
      distanceToEntryPercent: observedPrice == null
          ? null
          : candidate.approachDistancePercent(observedPrice),
      rawReasonCode:
          outcome == SignalOutcome.tp1 || outcome == SignalOutcome.tp2
          ? 'signal-outcome:${outcome!.name}'
          : 'candidate-transition:${candidate.transitionReason.name}',
      regime: journalEntry?.marketRegime,
    );
  }

  final RealtimeOpportunityCandidate candidate;
  final RealtimeRadarLane lane;
  final bool dataUncertain;
  final Duration age;
  final double? distanceToEntryPercent;
  final String rawReasonCode;
  final MarketRegime? regime;

  String laneLabel({required bool persian}) => switch (lane) {
    RealtimeRadarLane.forming => persian ? 'در حال شکل‌گیری' : 'Forming',
    RealtimeRadarLane.armed => persian ? 'آماده' : 'Armed',
    RealtimeRadarLane.triggered => persian ? 'تریگر شده' : 'Triggered',
    RealtimeRadarLane.managing => persian ? 'در حال مدیریت' : 'Managing',
    RealtimeRadarLane.missed => persian ? 'از دست‌رفته' : 'Missed',
  };

  String conciseReason({required bool persian}) {
    if (dataUncertain) {
      return persian
          ? 'ساختار ثبت شده، اما داده بازار برای اقدام تازه قابل اتکا نیست.'
          : 'The structure is recorded, but market data is not reliable for a new action.';
    }
    return switch (candidate.transitionReason) {
      OpportunityTransitionReason.created =>
        persian
            ? 'ستاپ شناسایی شده و شواهد در حال تکمیل است.'
            : 'The setup was detected and evidence is still forming.',
      OpportunityTransitionReason.evidenceImproved =>
        persian
            ? 'شواهد بهتر شده؛ هنوز فقط طبق تریگر اقدام می‌کنیم.'
            : 'Evidence improved; action still requires the trigger.',
      OpportunityTransitionReason.evidenceWeakened =>
        persian
            ? 'کیفیت شواهد افت کرده؛ فعلاً فقط زیر نظر.'
            : 'Evidence weakened; keep this on watch only.',
      OpportunityTransitionReason.entryApproaching =>
        persian
            ? 'قیمت به محدوده ورود نزدیک است؛ تریگر هنوز بسته نشده.'
            : 'Price is near entry; the closed trigger is not confirmed.',
      OpportunityTransitionReason.triggerConfirmed =>
        persian
            ? 'تریگر بسته‌شده تأیید شده و سناریو فعال است.'
            : 'The closed trigger is confirmed and the setup is active.',
      OpportunityTransitionReason.priceRanAway =>
        persian
            ? 'حرکت انجام شده؛ دنبال قیمت نمی‌رویم.'
            : 'Price already moved; do not chase it.',
      OpportunityTransitionReason.validityExpired =>
        persian
            ? 'اعتبار زمانی ستاپ تمام شده است.'
            : 'The setup validity window has expired.',
      OpportunityTransitionReason.structureInvalidated =>
        persian
            ? 'ساختار ستاپ نامعتبر شده است.'
            : 'The setup structure has been invalidated.',
      OpportunityTransitionReason.dataStale =>
        persian
            ? 'ساختار معتبر است، اما داده بازار تازه نیست.'
            : 'The structure is valid, but market data is stale.',
    };
  }

  String safeNextAction({required bool persian}) {
    if (dataUncertain) {
      return persian ? 'تا تازه‌شدن داده اقدام نکن' : 'Wait for fresh data';
    }
    return switch (lane) {
      RealtimeRadarLane.forming => persian ? 'فقط زیر نظر' : 'Watch only',
      RealtimeRadarLane.armed =>
        persian ? 'منتظر تأیید تریگر' : 'Wait for trigger confirmation',
      RealtimeRadarLane.triggered =>
        persian ? 'طرح ریسک را بررسی کن' : 'Review the risk plan',
      RealtimeRadarLane.managing =>
        persian ? 'حد ضرر را بی‌دلیل جابه‌جا نکن' : 'Do not widen the stop',
      RealtimeRadarLane.missed =>
        persian ? 'ورود جدید نکن' : 'Do not enter now',
    };
  }

  String urgencyLabel({required bool persian}) => switch (lane) {
    RealtimeRadarLane.triggered ||
    RealtimeRadarLane.managing => persian ? 'نیازمند توجه' : 'Needs attention',
    RealtimeRadarLane.armed => persian ? 'نزدیک' : 'Near',
    RealtimeRadarLane.forming => persian ? 'پایش' : 'Watch',
    RealtimeRadarLane.missed => persian ? 'بسته' : 'Closed',
  };

  String ageLabel({required bool persian}) {
    if (age.inSeconds < 60) {
      return persian ? '${age.inSeconds} ثانیه' : '${age.inSeconds}s';
    }
    if (age.inMinutes < 60) {
      return persian ? '${age.inMinutes} دقیقه' : '${age.inMinutes}m';
    }
    return persian ? '${age.inHours} ساعت' : '${age.inHours}h';
  }

  String distanceLabel({required bool persian}) {
    final value = distanceToEntryPercent;
    if (value == null) return persian ? 'نامشخص' : 'Unknown';
    if (value <= 0.005) return persian ? 'داخل محدوده' : 'In entry zone';
    return '${value.toStringAsFixed(value < 1 ? 2 : 1)}%';
  }
}

abstract final class RealtimeRadarProjection {
  static List<RealtimeRadarItemPresentation> build({
    required Iterable<RealtimeOpportunityCandidate> candidates,
    required Iterable<SignalJournalEntry> journal,
    required DateTime nowUtc,
    required bool realtimeOperational,
  }) {
    final journalById = <String, SignalJournalEntry>{
      for (final entry in journal) entry.setupId: entry,
    };
    return List.unmodifiable([
      for (final candidate in candidates)
        RealtimeRadarItemPresentation.fromEvidence(
          candidate: candidate,
          nowUtc: nowUtc,
          realtimeOperational: realtimeOperational,
          journalEntry: journalById[candidate.setupId],
        ),
    ]);
  }
}
