from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:120]!r}")
    write(path, text.replace(old, new, 1))


def replace_all(path: str, old: str, new: str, expected: int) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected} matches, found {count}: {old[:120]!r}")
    write(path, text.replace(old, new))


write(
    "src/client/quantara_app/lib/features/owner_alpha/application/signal_inbox_query.dart",
    r'''import '../domain/owner_alpha_models.dart';

enum SignalInboxFilter { all, opportunities, active, results, expired, taken }

enum SignalInboxSort { recommended, score, expiringSoon, newest, latestResult }

abstract final class SignalInboxQuery {
  static List<SignalJournalEntry> apply({
    required Iterable<SignalJournalEntry> entries,
    required SignalInboxFilter filter,
    required SignalInboxSort sort,
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) {
    final utcNow = now.toUtc();
    final result = entries.where((entry) {
      final taken = isTaken(entry.setupId);
      return switch (filter) {
        SignalInboxFilter.all => true,
        SignalInboxFilter.opportunities => isOpenOpportunity(
          entry,
          now: utcNow,
          taken: taken,
        ),
        SignalInboxFilter.active => isActive(entry),
        SignalInboxFilter.results => hasVisibleResult(entry),
        SignalInboxFilter.expired => isExpired(entry, now: utcNow),
        SignalInboxFilter.taken => taken,
      };
    }).toList(growable: false);
    result.sort(
      (left, right) => _compare(
        left,
        right,
        sort: sort,
        now: utcNow,
        isTaken: isTaken,
      ),
    );
    return result;
  }

  static int count({
    required Iterable<SignalJournalEntry> entries,
    required SignalInboxFilter filter,
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) => apply(
    entries: entries,
    filter: filter,
    sort: SignalInboxSort.recommended,
    now: now,
    isTaken: isTaken,
  ).length;

  static bool isOpenOpportunity(
    SignalJournalEntry entry, {
    required DateTime now,
    required bool taken,
  }) =>
      !taken &&
      !entry.closed &&
      entry.outcome == SignalOutcome.pendingEntry &&
      now.toUtc().isBefore(entry.validUntil);

  static bool isActive(SignalJournalEntry entry) =>
      !entry.closed &&
      (entry.outcome == SignalOutcome.active ||
          entry.outcome == SignalOutcome.tp1 ||
          entry.outcome == SignalOutcome.tp2);

  static bool hasVisibleResult(SignalJournalEntry entry) =>
      entry.outcome == SignalOutcome.stopped ||
      entry.outcome == SignalOutcome.tp1 ||
      entry.outcome == SignalOutcome.tp2 ||
      entry.outcome == SignalOutcome.tp3;

  static bool isExpired(SignalJournalEntry entry, {required DateTime now}) =>
      entry.outcome == SignalOutcome.expiredUntriggered ||
      entry.outcome == SignalOutcome.pendingEntry &&
          !now.toUtc().isBefore(entry.validUntil);

  static int _compare(
    SignalJournalEntry left,
    SignalJournalEntry right, {
    required SignalInboxSort sort,
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) {
    final result = switch (sort) {
      SignalInboxSort.recommended => _recommended(
        left,
        right,
        now: now,
        isTaken: isTaken,
      ),
      SignalInboxSort.score => _score(left, right),
      SignalInboxSort.expiringSoon => _expiringSoon(left, right, now: now),
      SignalInboxSort.newest => right.createdAt.compareTo(left.createdAt),
      SignalInboxSort.latestResult => _latestResult(left, right),
    };
    return result != 0 ? result : left.setupId.compareTo(right.setupId);
  }

  static int _recommended(
    SignalJournalEntry left,
    SignalJournalEntry right, {
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) {
    final leftBucket = _recommendedBucket(
      left,
      now: now,
      taken: isTaken(left.setupId),
    );
    final rightBucket = _recommendedBucket(
      right,
      now: now,
      taken: isTaken(right.setupId),
    );
    final bucket = leftBucket.compareTo(rightBucket);
    if (bucket != 0) return bucket;
    final score = _score(left, right);
    if (score != 0) return score;
    if (leftBucket == 0) return left.validUntil.compareTo(right.validUntil);
    return right.createdAt.compareTo(left.createdAt);
  }

  static int _recommendedBucket(
    SignalJournalEntry entry, {
    required DateTime now,
    required bool taken,
  }) {
    if (isOpenOpportunity(entry, now: now, taken: taken)) return 0;
    if (isActive(entry)) return 1;
    if (taken) return 2;
    if (hasVisibleResult(entry)) return 3;
    if (isExpired(entry, now: now)) return 4;
    return 5;
  }

  static int _score(SignalJournalEntry left, SignalJournalEntry right) {
    final confidence = right.confidencePercent.compareTo(
      left.confidencePercent,
    );
    if (confidence != 0) return confidence;
    final rewardRisk = (right.riskReward ?? 0).compareTo(left.riskReward ?? 0);
    if (rewardRisk != 0) return rewardRisk;
    return right.createdAt.compareTo(left.createdAt);
  }

  static int _expiringSoon(
    SignalJournalEntry left,
    SignalJournalEntry right, {
    required DateTime now,
  }) {
    final leftLive = left.outcome == SignalOutcome.pendingEntry &&
        now.isBefore(left.validUntil);
    final rightLive = right.outcome == SignalOutcome.pendingEntry &&
        now.isBefore(right.validUntil);
    if (leftLive != rightLive) return leftLive ? -1 : 1;
    if (leftLive) {
      final expiry = left.validUntil.compareTo(right.validUntil);
      if (expiry != 0) return expiry;
    }
    return _score(left, right);
  }

  static int _latestResult(
    SignalJournalEntry left,
    SignalJournalEntry right,
  ) {
    final leftResult = hasVisibleResult(left);
    final rightResult = hasVisibleResult(right);
    if (leftResult != rightResult) return leftResult ? -1 : 1;
    final leftAt = left.resolvedAt ?? left.createdAt;
    final rightAt = right.resolvedAt ?? right.createdAt;
    return rightAt.compareTo(leftAt);
  }
}
''',
)

write(
    "src/client/quantara_app/lib/features/owner_alpha/domain/profit_protection_policy.dart",
    r'''import '../../market_analysis/domain/market_regime_models.dart';
import 'owner_alpha_models.dart';

enum ProfitProtectionProfile {
  rangeDefense,
  trendBalance,
  breakoutRunner,
  transitionBalance,
  disorderDefense,
}

final class ProfitProtectionPlan {
  const ProfitProtectionPlan({
    required this.profile,
    required this.targetFractions,
    this.costBufferRate = 0.0017,
  });

  final ProfitProtectionProfile profile;
  final List<double> targetFractions;
  final double costBufferRate;

  double get minimumTargetFraction =>
      targetFractions.reduce((left, right) => left < right ? left : right);

  double get tp1RemainingTrigger =>
      (1 - targetFractions.first + 0.02).clamp(0, 1).toDouble();

  double get tp2RemainingTrigger =>
      (targetFractions.last + 0.02).clamp(0, 1).toDouble();
}

abstract final class ProfitProtectionPolicy {
  static const _range = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.rangeDefense,
    targetFractions: [0.55, 0.30, 0.15],
  );
  static const _trend = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.trendBalance,
    targetFractions: [0.45, 0.30, 0.25],
  );
  static const _breakout = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.breakoutRunner,
    targetFractions: [0.40, 0.25, 0.35],
  );
  static const _transition = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.transitionBalance,
    targetFractions: [0.40, 0.30, 0.30],
  );
  static const _disorder = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.disorderDefense,
    targetFractions: [0.60, 0.25, 0.15],
  );

  static ProfitProtectionPlan forRegime(MarketRegime regime) => switch (regime) {
    MarketRegime.range => _range,
    MarketRegime.directionalTrend => _trend,
    MarketRegime.breakoutExpansion => _breakout,
    MarketRegime.transition => _transition,
    MarketRegime.disorder => _disorder,
  };

  static ProfitProtectionPlan forIdea(TradeIdea idea) =>
      forRegime(idea.marketRegime);

  static ProfitProtectionPlan forJournal(SignalJournalEntry entry) =>
      forRegime(entry.marketRegime);
}
''',
)

# OwnerAlpha imports.
replace_once(
    "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart",
    "import '../application/owner_alpha_controller.dart';\n",
    "import '../application/owner_alpha_controller.dart';\nimport '../application/signal_inbox_query.dart';\n",
)
replace_once(
    "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart",
    "import '../domain/owner_alpha_models.dart';\n",
    "import '../domain/owner_alpha_models.dart';\nimport '../domain/profit_protection_policy.dart';\n",
)

# Journal metadata and regime persistence.
models = "src/client/quantara_app/lib/features/owner_alpha/domain/owner_alpha_models.dart"
replace_once(
    models,
    "import '../../market_analysis/domain/market_chart_models.dart';\n",
    "import '../../market_analysis/domain/market_chart_models.dart';\nimport '../../market_analysis/domain/market_regime_models.dart';\n",
)
replace_once(
    models,
    "    this.strategyVersion = '1.1',\n  });",
    "    this.strategyVersion = '1.1',\n    this.marketRegime = MarketRegime.transition,\n  });",
)
replace_once(
    models,
    "  final String strategyVersion;\n\n  DateTime get createdAt",
    "  final String strategyVersion;\n  final MarketRegime marketRegime;\n\n  DateTime get createdAt",
)
replace_once(
    models,
    "    required this.invalidation,\n    this.sizingCapital = 0,",
    "    required this.invalidation,\n    this.confidencePercent = 0,\n    this.riskReward,\n    this.marketRegime = MarketRegime.transition,\n    this.sizingCapital = 0,",
)
replace_once(
    models,
    "    invalidation: idea.invalidation,\n    sizingCapital: sizingCapital,",
    "    invalidation: idea.invalidation,\n    confidencePercent: idea.confidencePercent,\n    riskReward: idea.riskReward,\n    marketRegime: idea.marketRegime,\n    sizingCapital: sizingCapital,",
)
replace_once(
    models,
    "  final String invalidation;\n  final double sizingCapital;",
    "  final String invalidation;\n  final int confidencePercent;\n  final double? riskReward;\n  final MarketRegime marketRegime;\n  final double sizingCapital;",
)
replace_once(
    models,
    "    invalidation: invalidation,\n    sizingCapital: sizingCapital,",
    "    invalidation: invalidation,\n    confidencePercent: confidencePercent,\n    riskReward: riskReward,\n    marketRegime: marketRegime,\n    sizingCapital: sizingCapital,",
)
replace_once(
    models,
    "    'invalidation': invalidation,\n    'sizingCapital': sizingCapital,",
    "    'invalidation': invalidation,\n    'confidencePercent': confidencePercent,\n    'riskReward': riskReward,\n    'marketRegime': marketRegime.name,\n    'sizingCapital': sizingCapital,",
)
replace_once(
    models,
    "        invalidation: value['invalidation'] as String,\n        sizingCapital: (value['sizingCapital'] as num?)?.toDouble() ?? 0,",
    "        invalidation: value['invalidation'] as String,\n        confidencePercent: ((value['confidencePercent'] as num?)?.toInt() ?? 0)\n            .clamp(0, 100)\n            .toInt(),\n        riskReward: (value['riskReward'] as num?)?.toDouble(),\n        marketRegime: MarketRegime.values.firstWhere(\n          (item) => item.name == value['marketRegime'],\n          orElse: () => MarketRegime.transition,\n        ),\n        sizingCapital: (value['sizingCapital'] as num?)?.toDouble() ?? 0,",
)

# Advanced strategy regime propagation and 5m validity.
advanced = "src/client/quantara_app/lib/features/owner_alpha/data/advanced_strategy_engine.dart"
replace_all(
    advanced,
    "      strategy: AnalysisStrategy.structureZones,\n      long:",
    "      strategy: AnalysisStrategy.structureZones,\n      marketRegime: regime.regime,\n      long:",
    2,
)
replace_once(
    advanced,
    "      strategy: AnalysisStrategy.trendPullback,\n      long:",
    "      strategy: AnalysisStrategy.trendPullback,\n      marketRegime: regime.regime,\n      long:",
)
replace_once(
    advanced,
    "    required AnalysisStrategy strategy,\n    required bool long,",
    "    required AnalysisStrategy strategy,\n    required MarketRegime marketRegime,\n    required bool long,",
)
replace_once(
    advanced,
    "      strategy: strategy,\n      strategyVersion: version,",
    "      strategy: strategy,\n      strategyVersion: version,\n      marketRegime: marketRegime,",
)
replace_once(
    advanced,
    "  static Duration _durationFor(String timeframe) => switch (timeframe) {\n    '15m' =>",
    "  static Duration _durationFor(String timeframe) => switch (timeframe) {\n    '5m' => const Duration(minutes: 5),\n    '15m' =>",
)

strategy_v2 = "src/client/quantara_app/lib/features/owner_alpha/data/strategy_engine_v2.dart"
replace_once(
    strategy_v2,
    "      strategy: AnalysisStrategy.trendPullback,\n      capital:",
    "      strategy: AnalysisStrategy.trendPullback,\n      marketRegime: regime.regime,\n      capital:",
)
replace_once(
    strategy_v2,
    "      strategy: AnalysisStrategy.momentumContinuation,\n      capital:",
    "      strategy: AnalysisStrategy.momentumContinuation,\n      marketRegime: regime.regime,\n      capital:",
)
replace_once(
    strategy_v2,
    "    required AnalysisStrategy strategy,\n    required double capital,",
    "    required AnalysisStrategy strategy,\n    required MarketRegime marketRegime,\n    required double capital,",
)
replace_once(
    strategy_v2,
    "      strategy: strategy,\n      strategyVersion: version,",
    "      strategy: strategy,\n      strategyVersion: version,\n      marketRegime: marketRegime,",
)
replace_once(
    strategy_v2,
    "    return switch (timeframe) {\n      '15m' =>",
    "    return switch (timeframe) {\n      '5m' => const Duration(minutes: 5),\n      '15m' =>",
)

factory = "src/client/quantara_app/lib/features/owner_alpha/data/trade_idea_factory.dart"
replace_once(
    factory,
    "import '../../market_analysis/domain/market_chart_models.dart';\n",
    "import '../../market_analysis/domain/market_chart_models.dart';\nimport '../../market_analysis/domain/market_regime_models.dart';\n",
)
replace_once(
    factory,
    "      strategy: AnalysisStrategy.structureZones,\n      strategyVersion: strategyVersion(AnalysisStrategy.structureZones),",
    "      strategy: AnalysisStrategy.structureZones,\n      strategyVersion: strategyVersion(AnalysisStrategy.structureZones),\n      marketRegime: MarketRegime.directionalTrend,",
)

# Managed position persists the exact staged-exit profile.
managed = "src/client/quantara_app/lib/features/auto_trade/domain/local_live_trade_models.dart"
replace_once(
    managed,
    "import '../../owner_alpha/domain/owner_alpha_models.dart';\n",
    "import '../../market_analysis/domain/market_regime_models.dart';\nimport '../../owner_alpha/domain/owner_alpha_models.dart';\n",
)
replace_once(
    managed,
    "    this.stopOrderId,\n    this.stage = 0,",
    "    this.stopOrderId,\n    this.stage = 0,\n    this.targetFractions = const [0.40, 0.30, 0.30],\n    this.marketRegime = MarketRegime.transition,",
)
replace_once(
    managed,
    "  final String? stopOrderId;\n  final int stage;",
    "  final String? stopOrderId;\n  final int stage;\n  final List<double> targetFractions;\n  final MarketRegime marketRegime;",
)
replace_once(
    managed,
    "        stopOrderId: stopOrderId ?? this.stopOrderId,\n        stage: stage ?? this.stage,",
    "        stopOrderId: stopOrderId ?? this.stopOrderId,\n        stage: stage ?? this.stage,\n        targetFractions: targetFractions,\n        marketRegime: marketRegime,",
)
replace_once(
    managed,
    "    'stopOrderId': stopOrderId,\n    'stage': stage,",
    "    'stopOrderId': stopOrderId,\n    'stage': stage,\n    'targetFractions': targetFractions,\n    'marketRegime': marketRegime.name,",
)
replace_once(
    managed,
    "        stage: (json['stage'] as num?)?.toInt() ?? 0,\n      );",
    "        stage: (json['stage'] as num?)?.toInt() ?? 0,\n        targetFractions: _targetFractionsFromJson(json['targetFractions']),\n        marketRegime: MarketRegime.values.firstWhere(\n          (item) => item.name == json['marketRegime'],\n          orElse: () => MarketRegime.transition,\n        ),\n      );\n\n  static List<double> _targetFractionsFromJson(Object? value) {\n    final parsed = (value as List<Object?>? ?? const [])\n        .whereType<num>()\n        .map((item) => item.toDouble())\n        .toList(growable: false);\n    final total = parsed.fold<double>(0, (sum, item) => sum + item);\n    if (parsed.length != 3 ||\n        parsed.any((item) => !item.isFinite || item <= 0) ||\n        (total - 1).abs() > 0.0001) {\n      return const [0.40, 0.30, 0.30];\n    }\n    return List.unmodifiable(parsed);\n  }",
)

# Local live uses regime-aware fractions and preserves stage-2 stop repair.
service = "src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart"
replace_once(
    service,
    "import '../../owner_alpha/data/trade_idea_factory.dart';\nimport '../../owner_alpha/domain/owner_alpha_models.dart';",
    "import '../../owner_alpha/data/trade_idea_factory.dart';\nimport '../../owner_alpha/domain/owner_alpha_models.dart';\nimport '../../owner_alpha/domain/profit_protection_policy.dart';",
)
replace_once(
    service,
    "\n  static const _targetFractions = <double>[0.40, 0.30, 0.30];\n",
    "\n",
)
replace_once(
    service,
    "      final markPrice = await exchange.fetchMarkPrice(idea.symbol);",
    "      final profitPlan = ProfitProtectionPolicy.forIdea(idea);\n      final markPrice = await exchange.fetchMarkPrice(idea.symbol);",
)
replace_once(
    service,
    "      if (quantity < rules.minimumQuantity / _targetFractions.last ||",
    "      if (quantity <\n              rules.minimumQuantity / profitPlan.minimumTargetFraction ||",
)
replace_once(
    service,
    "      if (quantity < rules.minimumQuantity * 3) {",
    "      if (quantity <\n          rules.minimumQuantity / profitPlan.minimumTargetFraction) {",
)
replace_once(
    service,
    "        quantity * _targetFractions[0],",
    "        quantity * profitPlan.targetFractions[0],",
)
replace_once(
    service,
    "        quantity * _targetFractions[1],",
    "        quantity * profitPlan.targetFractions[1],",
)
replace_once(
    service,
    "          stopOrderId: stopOrderId,\n        ),",
    "          stopOrderId: stopOrderId,\n          targetFractions: profitPlan.targetFractions,\n          marketRegime: idea.marketRegime,\n        ),",
)
replace_once(
    service,
    "        'Entry fill, full stop and three staged targets confirmed.',",
    "        'Entry fill, full stop and three regime-aware staged targets confirmed (${profitPlan.profile.name}).',",
)
replace_once(
    service,
    "            stopLoss: managed.stage >= 1\n                ? _breakEvenStop(managed)\n                : managed.originalStopLoss,",
    "            stopLoss: managed.stage >= 2\n                ? managed.targets.first\n                : managed.stage >= 1\n                ? _breakEvenStop(managed)\n                : managed.originalStopLoss,",
)
replace_once(
    service,
    "      if (managed.stage < 1 && ratio <= 0.62) {",
    "      final tp1Trigger =\n          (1 - managed.targetFractions.first + 0.02).clamp(0, 1);\n      final tp2Trigger =\n          (managed.targetFractions.last + 0.02).clamp(0, 1);\n      if (managed.stage < 1 && ratio <= tp1Trigger) {",
)
replace_once(
    service,
    "      if (next.stage < 2 && ratio <= 0.32) {",
    "      if (next.stage < 2 && ratio <= tp2Trigger) {",
)
replace_once(
    service,
    "          'TP1 largest reduction observed; remaining position moved beyond break-even including costs.',",
    "          'TP1 save-profit reduction observed; remaining position moved beyond break-even including costs.',",
)

# Paper outcomes mirror the selected profile.
evaluator = "src/client/quantara_app/lib/features/owner_alpha/data/signal_outcome_evaluator.dart"
replace_once(
    evaluator,
    "import '../domain/owner_alpha_models.dart';\n",
    "import '../domain/owner_alpha_models.dart';\nimport '../domain/profit_protection_policy.dart';\n",
)
replace_once(
    evaluator,
    "  static const _targetFractions = <double>[0.40, 0.30, 0.30];\n",
    "",
)
replace_once(
    evaluator,
    "    final reachedTargets = highestTarget\n        .clamp(0, _targetFractions.length)\n        .toInt();",
    "    final targetFractions = ProfitProtectionPolicy.forJournal(\n      entry,\n    ).targetFractions;\n    final reachedTargets = highestTarget\n        .clamp(0, targetFractions.length)\n        .toInt();",
)
replace_once(
    evaluator,
    "      final trancheSize = entry.positionSize * _targetFractions[index];",
    "      final trancheSize = entry.positionSize * targetFractions[index];",
)

# Signal Inbox query UI and familiar terminology.
signals = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_signals.dart"
replace_once(signals, "\nenum _SignalFilter { all, live, taken, expired }\n", "\n")
replace_once(
    signals,
    "  _SignalFilter _filter = _SignalFilter.all;",
    "  SignalInboxFilter _filter = SignalInboxFilter.all;\n  SignalInboxSort _sort = SignalInboxSort.recommended;",
)
old_filter_logic = r'''    final filtered = all
        .where((entry) {
          final lifecycle = entry.lifecycle(
            now,
            taken: controller.isTaken(entry.setupId),
          );
          return switch (_filter) {
            _SignalFilter.all => true,
            _SignalFilter.live =>
              lifecycle == SignalLifecycle.fresh ||
                  lifecycle == SignalLifecycle.expiring,
            _SignalFilter.taken => lifecycle == SignalLifecycle.taken,
            _SignalFilter.expired =>
              lifecycle == SignalLifecycle.expired ||
                  lifecycle == SignalLifecycle.closed,
          };
        })
        .toList(growable: false);'''
new_filter_logic = r'''    final filtered = SignalInboxQuery.apply(
      entries: all,
      filter: _filter,
      sort: _sort,
      now: now,
      isTaken: controller.isTaken,
    );
    int count(SignalInboxFilter filter) => SignalInboxQuery.count(
      entries: all,
      filter: filter,
      now: now,
      isTaken: controller.isTaken,
    );'''
replace_once(signals, old_filter_logic, new_filter_logic)
old_segments = r'''        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_SignalFilter>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _SignalFilter.all,
                label: Text(_t('همه', 'All')),
              ),
              ButtonSegment(
                value: _SignalFilter.live,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(_t('معتبر', 'Live')),
              ),
              ButtonSegment(
                value: _SignalFilter.taken,
                icon: const Icon(Icons.bookmark_rounded),
                label: Text(_t('گرفته‌شده', 'Taken')),
              ),
              ButtonSegment(
                value: _SignalFilter.expired,
                label: Text(_t('بایگانی', 'Archive')),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.single),
          ),
        ),
        const SizedBox(height: 16),'''
new_segments = r'''        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<SignalInboxFilter>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: SignalInboxFilter.all,
                label: Text(_t('همه ${all.length}', 'All ${all.length}')),
              ),
              ButtonSegment(
                value: SignalInboxFilter.opportunities,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(
                  _t(
                    'فرصت باز ${count(SignalInboxFilter.opportunities)}',
                    'Open ${count(SignalInboxFilter.opportunities)}',
                  ),
                ),
              ),
              ButtonSegment(
                value: SignalInboxFilter.active,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: Text(
                  _t(
                    'فعال ${count(SignalInboxFilter.active)}',
                    'Active ${count(SignalInboxFilter.active)}',
                  ),
                ),
              ),
              ButtonSegment(
                value: SignalInboxFilter.results,
                icon: const Icon(Icons.query_stats_rounded),
                label: Text(
                  _t(
                    'نتیجه‌دار ${count(SignalInboxFilter.results)}',
                    'Results ${count(SignalInboxFilter.results)}',
                  ),
                ),
              ),
              ButtonSegment(
                value: SignalInboxFilter.expired,
                icon: const Icon(Icons.timer_off_outlined),
                label: Text(
                  _t(
                    'منقضی ${count(SignalInboxFilter.expired)}',
                    'Expired ${count(SignalInboxFilter.expired)}',
                  ),
                ),
              ),
              ButtonSegment(
                value: SignalInboxFilter.taken,
                icon: const Icon(Icons.bookmark_rounded),
                label: Text(
                  _t(
                    'گرفتم ${count(SignalInboxFilter.taken)}',
                    'Taken ${count(SignalInboxFilter.taken)}',
                  ),
                ),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.single),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SignalInboxSort>(
          initialValue: _sort,
          decoration: InputDecoration(
            labelText: _t('مرتب‌سازی پیشنهادها', 'Sort setups'),
            prefixIcon: const Icon(Icons.sort_rounded),
          ),
          items: [
            for (final sort in SignalInboxSort.values)
              DropdownMenuItem(value: sort, child: Text(_sortLabel(sort))),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sort = value);
          },
        ),
        const SizedBox(height: 16),'''
replace_once(signals, old_segments, new_segments)
replace_once(
    signals,
    "  Future<void> _editNote(SignalJournalEntry entry) async {",
    r'''  String _sortLabel(SignalInboxSort value) => switch (value) {
    SignalInboxSort.recommended => _t('پیشنهادی؛ فرصت‌های بهتر اول', 'Recommended'),
    SignalInboxSort.score => _t('بیشترین امتیاز', 'Highest score'),
    SignalInboxSort.expiringSoon => _t('نزدیک‌ترین انقضا', 'Expiring soon'),
    SignalInboxSort.newest => _t('جدیدترین', 'Newest'),
    SignalInboxSort.latestResult => _t('آخرین نتیجه', 'Latest result'),
  };

  Future<void> _editNote(SignalJournalEntry entry) async {''',
)
replace_once(
    signals,
    "            style: Theme.of(context).textTheme.bodySmall,\n          ),\n        ],\n      ),\n    );\n  }\n\n  String _strategyLabel",
    "            style: Theme.of(context).textTheme.bodySmall,\n          ),\n          const SizedBox(height: 10),\n          Text(\n            _t(\n              context,\n              'منطق سیو سود ثابت نیست: اول می‌سنجیم بازار روند است، رنج است یا شکست دارد؛ بعد حجم TP1، رانر و نقطه ریسک‌فری متناسب با همان سناریو انتخاب می‌شود.',\n              'Profit protection is regime-aware: trend, range and breakout setups use different TP1, runner and break-even sizing.',\n            ),\n            style: Theme.of(context).textTheme.bodySmall?.copyWith(\n              color: QuantaraColors.cyan,\n              fontWeight: FontWeight.w700,\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n\n  String _strategyLabel",
)
replace_once(
    signals,
    "    final lifecycle = entry.lifecycle(now, taken: taken);\n    final color = switch (lifecycle) {",
    "    final lifecycle = entry.lifecycle(now, taken: taken);\n    final profitPlan = ProfitProtectionPolicy.forJournal(entry);\n    final color = switch (lifecycle) {",
)
replace_once(
    signals,
    "                StatusPill(\n                  label: _outcomeLabel(context),\n                  color: _outcomeColor(context),\n                  icon: _outcomeIcon,\n                ),",
    "                StatusPill(\n                  label: _outcomeLabel(context),\n                  color: _outcomeColor(context),\n                  icon: _outcomeIcon,\n                ),\n                if (entry.confidencePercent > 0)\n                  StatusPill(\n                    label: _t(\n                      context,\n                      'امتیاز ${entry.confidencePercent}',\n                      'Score ${entry.confidencePercent}',\n                    ),\n                    color: QuantaraColors.cyan,\n                    icon: Icons.auto_graph_rounded,\n                  ),\n                if (entry.riskReward != null)\n                  StatusPill(\n                    label: 'R:R ${entry.riskReward!.toStringAsFixed(2)}',\n                    color: QuantaraColors.success,\n                  ),\n                StatusPill(\n                  label: _profitProfileLabel(context, profitPlan.profile),\n                  color: QuantaraColors.warning,\n                  icon: Icons.savings_outlined,\n                ),",
)
replace_once(
    signals,
    "            Text(entry.summary),\n            if (priority == SignalTimeframePriorityKind.primary)",
    "            Text(entry.summary),\n            const SizedBox(height: 8),\n            Text(\n              _profitProtectionHint(context, profitPlan),\n              style: Theme.of(context).textTheme.bodySmall?.copyWith(\n                color: QuantaraColors.warning,\n                fontWeight: FontWeight.w700,\n              ),\n            ),\n            if (priority == SignalTimeframePriorityKind.primary)",
)
replace_once(
    signals,
    "  String _direction(BuildContext context) =>",
    r'''  String _profitProfileLabel(
    BuildContext context,
    ProfitProtectionProfile profile,
  ) => switch (profile) {
    ProfitProtectionProfile.rangeDefense =>
      _t(context, 'رنج؛ سیو سریع', 'Range defense'),
    ProfitProtectionProfile.trendBalance =>
      _t(context, 'روند؛ متعادل', 'Trend balance'),
    ProfitProtectionProfile.breakoutRunner =>
      _t(context, 'شکست؛ رانر بزرگ', 'Breakout runner'),
    ProfitProtectionProfile.transitionBalance =>
      _t(context, 'گذار؛ متعادل', 'Transition balance'),
    ProfitProtectionProfile.disorderDefense =>
      _t(context, 'آشفته؛ دفاعی', 'Disorder defense'),
  };

  String _profitProtectionHint(
    BuildContext context,
    ProfitProtectionPlan plan,
  ) {
    final parts = plan.targetFractions
        .map((value) => (value * 100).round())
        .join(' / ');
    return _t(
      context,
      'پلن سیو سود $parts٪ است؛ بعد از TP1 باقی‌مانده با احتساب هزینه‌ها ریسک‌فری می‌شود و بعد از TP2 استاپ رانر روی TP1 می‌آید.',
      'Save-profit plan: $parts%. After TP1 the remainder moves beyond break-even including costs; after TP2 the runner stop moves to TP1.',
    );
  }

  String _direction(BuildContext context) =>''',
)
replace_once(
    signals,
    "اگر بعد از TP حد ضرر بخورد، خروج پله‌ای مساوی لحاظ می‌شود؛ کارمزد و لغزش فرضی هم کسر شده‌اند.",
    "اگر بعد از TP حد ضرر بخورد، خروج پله‌ای متناسب با روند، رنج یا شکست و جابه‌جایی ریسک‌فری لحاظ می‌شود؛ کارمزد و لغزش فرضی هم کسر شده‌اند.",
)
replace_once(
    signals,
    "If price stops after a TP, equal scale-outs are modeled; estimated fees and slippage are deducted.",
    "If price stops after a TP, regime-aware scale-outs and break-even movement are modeled; estimated fees and slippage are deducted.",
)

# Version and artifact labels.
pubspec = "src/client/quantara_app/pubspec.yaml"
replace_once(pubspec, "version: 1.0.1+101", "version: 1.0.2+102")
ci = ".github/workflows/flutter-ci.yml"
text = read(ci)
text = text.replace("1.0.1", "1.0.2")
write(ci, text)

# Tests.
write(
    "src/client/quantara_app/test/signal_inbox_query_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/signal_inbox_query.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 10);

  test('recommended ordering surfaces open high-score opportunities first', () {
    final entries = [
      _entry('result', score: 95, outcome: SignalOutcome.tp3),
      _entry('low', score: 62),
      _entry('high', score: 84),
      _entry('active', score: 90, outcome: SignalOutcome.active),
    ];

    final result = SignalInboxQuery.apply(
      entries: entries,
      filter: SignalInboxFilter.all,
      sort: SignalInboxSort.recommended,
      now: now,
      isTaken: (_) => false,
    );

    expect(result.map((entry) => entry.setupId), [
      'high',
      'low',
      'active',
      'result',
    ]);
  });

  test('filters distinguish opportunities, active, results and expired', () {
    final entries = [
      _entry('open'),
      _entry('active', outcome: SignalOutcome.active),
      _entry('tp1', outcome: SignalOutcome.tp1),
      _entry('stopped', outcome: SignalOutcome.stopped),
      _entry(
        'expired',
        validUntil: now.subtract(const Duration(minutes: 1)),
      ),
    ];

    List<String> ids(SignalInboxFilter filter) => SignalInboxQuery.apply(
      entries: entries,
      filter: filter,
      sort: SignalInboxSort.newest,
      now: now,
      isTaken: (_) => false,
    ).map((entry) => entry.setupId).toList();

    expect(ids(SignalInboxFilter.opportunities), ['open']);
    expect(ids(SignalInboxFilter.active), containsAll(['active', 'tp1']));
    expect(ids(SignalInboxFilter.results), containsAll(['tp1', 'stopped']));
    expect(ids(SignalInboxFilter.expired), ['expired']);
  });

  test('score sort uses persisted confidence then reward risk', () {
    final result = SignalInboxQuery.apply(
      entries: [
        _entry('rr-low', score: 80, rewardRisk: 1.6),
        _entry('score-high', score: 90, rewardRisk: 1.2),
        _entry('rr-high', score: 80, rewardRisk: 2.4),
      ],
      filter: SignalInboxFilter.all,
      sort: SignalInboxSort.score,
      now: now,
      isTaken: (_) => false,
    );

    expect(result.map((entry) => entry.setupId), [
      'score-high',
      'rr-high',
      'rr-low',
    ]);
  });
}

SignalJournalEntry _entry(
  String id, {
  int score = 70,
  double? rewardRisk = 1.8,
  SignalOutcome outcome = SignalOutcome.pendingEntry,
  DateTime? validUntil,
}) => SignalJournalEntry(
  setupId: id,
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test',
  createdAt: DateTime.utc(2026, 8, 2, 9),
  validUntil: validUntil ?? DateTime.utc(2026, 8, 2, 11),
  entryLower: 99,
  entryUpper: 100,
  stopLoss: 98,
  targets: const [102, 104, 106],
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
  confidencePercent: score,
  riskReward: rewardRisk,
  outcome: outcome,
);
''',
)

write(
    "src/client/quantara_app/test/profit_protection_policy_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  test('every profile is a valid three-stage plan with TP1 largest', () {
    for (final regime in MarketRegime.values) {
      final plan = ProfitProtectionPolicy.forRegime(regime);
      expect(plan.targetFractions, hasLength(3));
      expect(
        plan.targetFractions.fold<double>(0, (sum, value) => sum + value),
        closeTo(1, 0.000001),
      );
      expect(plan.targetFractions.first, greaterThanOrEqualTo(plan.targetFractions[1]));
      expect(plan.targetFractions.first, greaterThanOrEqualTo(plan.targetFractions[2]));
      expect(plan.tp1RemainingTrigger, greaterThan(plan.tp2RemainingTrigger));
    }
  });

  test('range saves faster while breakout preserves a larger runner', () {
    final range = ProfitProtectionPolicy.forRegime(MarketRegime.range);
    final breakout = ProfitProtectionPolicy.forRegime(
      MarketRegime.breakoutExpansion,
    );

    expect(range.targetFractions.first, greaterThan(breakout.targetFractions.first));
    expect(range.targetFractions.last, lessThan(breakout.targetFractions.last));
  });

  test('legacy transition profile preserves the 40/30/30 ladder', () {
    expect(
      ProfitProtectionPolicy.forRegime(
        MarketRegime.transition,
      ).targetFractions,
      const [0.40, 0.30, 0.30],
    );
  });
}
''',
)

write(
    "src/client/quantara_app/test/signal_journal_metadata_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('journal persists score reward-risk and market regime', () {
    final entry = _entry();
    final restored = SignalJournalEntry.tryFromJson(entry.toJson());

    expect(restored, isNotNull);
    expect(restored!.confidencePercent, 88);
    expect(restored.riskReward, 2.4);
    expect(restored.marketRegime, MarketRegime.breakoutExpansion);
  });

  test('legacy journal without metadata remains readable', () {
    final json = _entry().toJson()
      ..remove('confidencePercent')
      ..remove('riskReward')
      ..remove('marketRegime');
    final restored = SignalJournalEntry.tryFromJson(json);

    expect(restored, isNotNull);
    expect(restored!.confidencePercent, 0);
    expect(restored.riskReward, isNull);
    expect(restored.marketRegime, MarketRegime.transition);
  });
}

SignalJournalEntry _entry() => SignalJournalEntry(
  setupId: 'BTCUSDT|5m|test',
  symbol: 'BTCUSDT',
  timeframe: '5m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.momentumContinuation,
  strategyVersion: 'test',
  createdAt: DateTime.utc(2026, 8, 2, 9),
  validUntil: DateTime.utc(2026, 8, 2, 9, 15),
  entryLower: 99,
  entryUpper: 100,
  stopLoss: 98,
  targets: const [102, 104, 106],
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
  confidencePercent: 88,
  riskReward: 2.4,
  marketRegime: MarketRegime.breakoutExpansion,
);
''',
)
