import '../domain/owner_alpha_models.dart';

enum ActionableSignalStage {
  forming,
  armed,
  triggered,
  managing,
  missed,
  resolved,
  dataUncertain,
}

/// Pure, read-only projection for the first viewport of a signal card.
///
/// It deliberately derives copy only from persisted signal outcome and current
/// public-market freshness. It does not invent execution, risk, or allocator
/// decisions that are absent from domain evidence.
final class ActionableSignalPresentation {
  const ActionableSignalPresentation._({
    required this.stage,
    required this.rawReasonCode,
    required this.distanceToEntryPercent,
    required this.marketAge,
    required this.isDataUncertain,
    required this.isInsideEntryZone,
  });

  factory ActionableSignalPresentation.fromEvidence({
    required SignalJournalEntry entry,
    required DateTime nowUtc,
    required bool marketDataFresh,
    double? currentPrice,
    DateTime? quoteObservedAtUtc,
  }) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'UTC is required.');
    }

    final usablePrice =
        currentPrice != null &&
            currentPrice.isFinite &&
            currentPrice > 0 &&
            entry.entryLower != null &&
            entry.entryUpper != null
        ? currentPrice
        : null;
    final insideEntry =
        usablePrice != null &&
        usablePrice >= entry.entryLower! &&
        usablePrice <= entry.entryUpper!;
    final uncertain = !marketDataFresh || usablePrice == null;
    final expired = !nowUtc.isBefore(entry.validUntil.toUtc());

    final stage = uncertain && entry.outcome == SignalOutcome.pendingEntry
        ? ActionableSignalStage.dataUncertain
        : switch (entry.outcome) {
            SignalOutcome.pendingEntry when expired =>
              ActionableSignalStage.missed,
            SignalOutcome.pendingEntry when insideEntry =>
              ActionableSignalStage.armed,
            SignalOutcome.pendingEntry => ActionableSignalStage.forming,
            SignalOutcome.active => ActionableSignalStage.triggered,
            SignalOutcome.tp1 ||
            SignalOutcome.tp2 => ActionableSignalStage.managing,
            SignalOutcome.expiredUntriggered => ActionableSignalStage.missed,
            SignalOutcome.stopped ||
            SignalOutcome.tp3 => ActionableSignalStage.resolved,
          };

    return ActionableSignalPresentation._(
      stage: stage,
      rawReasonCode: uncertain && entry.outcome == SignalOutcome.pendingEntry
          ? 'market-data-uncertain:${entry.outcome.name}'
          : 'signal-outcome:${entry.outcome.name}',
      distanceToEntryPercent: usablePrice == null
          ? null
          : _distanceToEntry(
              price: usablePrice,
              lower: entry.entryLower!,
              upper: entry.entryUpper!,
            ),
      marketAge: quoteObservedAtUtc == null
          ? null
          : _nonNegative(nowUtc.difference(quoteObservedAtUtc.toUtc())),
      isDataUncertain: uncertain,
      isInsideEntryZone: insideEntry,
    );
  }

  final ActionableSignalStage stage;
  final String rawReasonCode;
  final double? distanceToEntryPercent;
  final Duration? marketAge;
  final bool isDataUncertain;
  final bool isInsideEntryZone;

  String stageLabel({required bool persian}) => switch (stage) {
    ActionableSignalStage.forming => persian ? 'در حال شکل‌گیری' : 'Forming',
    ActionableSignalStage.armed => persian ? 'آماده تریگر' : 'Armed',
    ActionableSignalStage.triggered => persian ? 'تریگر شده' : 'Triggered',
    ActionableSignalStage.managing => persian ? 'در حال مدیریت' : 'Managing',
    ActionableSignalStage.missed => persian ? 'از دست‌رفته' : 'Missed',
    ActionableSignalStage.resolved => persian ? 'پایان‌یافته' : 'Resolved',
    ActionableSignalStage.dataUncertain =>
      persian ? 'داده نامطمئن' : 'Data uncertain',
  };

  String conciseReason({required bool persian}) => switch (stage) {
    ActionableSignalStage.forming =>
      persian
          ? 'ناحیه معتبر است؛ قیمت هنوز به محدوده ورود نرسیده.'
          : 'The zone is valid; price has not reached entry yet.',
    ActionableSignalStage.armed =>
      persian
          ? 'قیمت داخل محدوده است؛ تریگر بسته‌شده هنوز تأیید نشده.'
          : 'Price is in the zone; the closed trigger is not confirmed yet.',
    ActionableSignalStage.triggered =>
      persian
          ? 'تریگر ثبت شده؛ وضعیت فعال است.'
          : 'The trigger is confirmed; the setup is active.',
    ActionableSignalStage.managing =>
      persian
          ? 'بخشی از مسیر طی شده؛ مدیریت با ساختار ادامه دارد.'
          : 'The setup has progressed; management continues by structure.',
    ActionableSignalStage.missed =>
      persian
          ? 'فرصت بدون تریگر معتبر پایان یافته؛ دنبال قیمت نمی‌رویم.'
          : 'The opportunity ended without a valid trigger; do not chase.',
    ActionableSignalStage.resolved =>
      persian
          ? 'نتیجه ثبت شده؛ اقدام جدیدی از این کارت انجام نمی‌شود.'
          : 'The outcome is recorded; this card has no new action.',
    ActionableSignalStage.dataUncertain =>
      persian
          ? 'ساختار ثبت شده، اما داده بازار برای اقدام تازه قابل اتکا نیست.'
          : 'The structure is recorded, but market data is not reliable for a new action.',
  };

  String safeNextAction({required bool persian}) => switch (stage) {
    ActionableSignalStage.forming => persian ? 'فقط زیر نظر' : 'Watch only',
    ActionableSignalStage.armed =>
      persian ? 'منتظر تأیید تریگر' : 'Wait for trigger confirmation',
    ActionableSignalStage.triggered =>
      persian ? 'طرح ریسک را بررسی کن' : 'Review the risk plan',
    ActionableSignalStage.managing =>
      persian ? 'حد ضرر را بی‌دلیل جابه‌جا نکن' : 'Do not widen the stop',
    ActionableSignalStage.missed =>
      persian ? 'ورود جدید نکن' : 'Do not enter now',
    ActionableSignalStage.resolved =>
      persian ? 'نتیجه را مرور کن' : 'Review the outcome',
    ActionableSignalStage.dataUncertain =>
      persian ? 'تا تازه‌شدن داده اقدام نکن' : 'Wait for fresh data',
  };

  String distanceLabel({required bool persian}) {
    final value = distanceToEntryPercent;
    if (value == null) return persian ? 'نامشخص' : 'Unknown';
    if (value <= 0.005) return persian ? 'داخل محدوده' : 'In entry zone';
    return '${value.toStringAsFixed(value < 1 ? 2 : 1)}%';
  }

  String ageLabel({required bool persian}) {
    final age = marketAge;
    if (age == null) return persian ? 'نامشخص' : 'Unknown';
    if (age.inSeconds < 60) {
      return persian ? '${age.inSeconds} ثانیه' : '${age.inSeconds}s';
    }
    if (age.inMinutes < 60) {
      return persian ? '${age.inMinutes} دقیقه' : '${age.inMinutes}m';
    }
    return persian ? '${age.inHours} ساعت' : '${age.inHours}h';
  }

  static double _distanceToEntry({
    required double price,
    required double lower,
    required double upper,
  }) {
    if (price < lower) return (lower - price) / price * 100;
    if (price > upper) return (price - upper) / price * 100;
    return 0;
  }

  static Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;
}
