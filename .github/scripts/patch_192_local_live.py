from pathlib import Path

p = Path('src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart')
s = p.read_text()
s = s.replace(
    "import '../../owner_alpha/data/bitunix_owner_alpha_repository.dart';",
    "import '../../decision_core/domain/economic_opportunity_models.dart';\nimport '../../owner_alpha/data/bitunix_owner_alpha_repository.dart';",
)
s = s.replace(
    "import 'local_live_canonical_decision.dart';",
    "import 'local_live_canonical_decision.dart';\nimport 'local_live_economic_ranking.dart';",
)
s = s.replace(
    "const localLiveAuditKey = 'quantara.local-live.audit.v1';",
    "const localLiveAuditKey = 'quantara.local-live.audit.v1';\nconst localLiveRankingJournalKey = 'quantara.local-live.ranking-journal.v1';",
)
s = s.replace(
    "  final List<LocalLiveAuditEvent> _audit = [];",
    "  final List<LocalLiveAuditEvent> _audit = [];\n  final List<OpportunityRankingJournalRecord> _rankingJournal = [];",
)
old = """      final rankedIdeas = _rankPrimaryIdeas(ideas);
      if (rankedIdeas.isEmpty) {"""
new = """      final lastPrices = <String, double>{
        for (final result in snapshot.radar)
          result.quote.symbol.trim().toUpperCase(): result.quote.lastPrice,
      };
      final concentrationPenalty = exchangePositions.isEmpty
          ? 0.0
          : math.min(
              0.5,
              exchangePositions.where((item) => item.quantity > 0).length *
                  0.12,
            );
      final rankedIdeas = LocalLiveEconomicRanking.rank(
        ideas: ideas,
        lastPrices: lastPrices,
        evaluatedAtUtc: DateTime.now().toUtc(),
        concentrationPenaltyBySymbol: {
          for (final idea in ideas)
            idea.symbol.trim().toUpperCase(): concentrationPenalty,
        },
      );
      if (rankedIdeas.isEmpty) {"""
if old not in s:
    raise SystemExit('ranking call target not found')
s = s.replace(old, new, 1)

old = """      for (final idea in rankedIdeas) {
        if (_executedSetupIds.contains(idea.setupId)) {"""
new = """      for (final rankedIdea in rankedIdeas) {
        final idea = rankedIdea.idea;
        await _recordRankingOutcome(
          rankedIdea,
          OpportunityRankingOutcome.ranked,
          'Candidate admitted to deterministic economic ordering.',
        );
        if (_executedSetupIds.contains(idea.setupId)) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.duplicateSkipped,
            'Setup already executed in local-live history.',
          );"""
if old not in s:
    raise SystemExit('ranking loop target not found')
s = s.replace(old, new, 1)
s = s.replace(
    "'The highest-ranked setup was already executed in this local-live history.'",
    "'The ranked setup was already executed in this local-live history.'",
)

old = """        if (idea.isExpiredAt(DateTime.now().toUtc()) ||
            idea.stopLoss == null ||
            idea.targets.length < 3 ||
            idea.entryLower == null ||
            idea.entryUpper == null) {
          _auditEvent("""
new = """        if (idea.isExpiredAt(DateTime.now().toUtc()) ||
            idea.stopLoss == null ||
            idea.targets.length < 3 ||
            idea.entryLower == null ||
            idea.entryUpper == null) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.staleOrIncomplete,
            'Ranked setup expired or lacked a complete protected plan.',
          );
          _auditEvent("""
if old not in s:
    raise SystemExit('expiry target not found')
s = s.replace(old, new, 1)
s = s.replace(
    "'The highest-ranked setup was expired or missing a complete protected plan.'",
    "'The ranked setup was expired or missing a complete protected plan.'",
)

old = """        if (!canonical.eligible) {
          _auditEvent("""
new = """        if (!canonical.eligible) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.canonicalRejected,
            'Canonical decision rejected: ${canonical.rejection.name}.',
          );
          _auditEvent("""
if old not in s:
    raise SystemExit('canonical target not found')
s = s.replace(old, new, 1)

old = """        if (!reservation.decision.allowed ||
            !reservation.decision.liveExecutionAllowed) {
          _auditEvent("""
new = """        if (!reservation.decision.allowed ||
            !reservation.decision.liveExecutionAllowed) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.portfolioRejected,
            'Portfolio reservation rejected: ${reservation.decision.reason.name}.',
          );
          _auditEvent("""
if old not in s:
    raise SystemExit('reservation target not found')
s = s.replace(old, new, 1)

old = """          final clientId = _clientId(idea);
          orderRequestStarted = true;
          final placed = await exchange.placeMarketEntry("""
new = """          final clientId = _clientId(idea);
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.executionAttempted,
            'All deterministic pre-order gates passed; protected entry request may start.',
          );
          orderRequestStarted = true;
          final placed = await exchange.placeMarketEntry("""
if old not in s:
    raise SystemExit('execution attempt target not found')
s = s.replace(old, new, 1)

old = """          _auditEvent(
            'position_protected',"""
new = """          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.entered,
            'Entry fill and exchange-native protection were confirmed.',
          );
          _auditEvent(
            'position_protected',"""
if old not in s:
    raise SystemExit('protected target not found')
s = s.replace(old, new, 1)

old = """        } on Object catch (error) {
          final reservationId = activeReservationId;"""
new = """        } on Object catch (error) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.executionFailed,
            'Protected entry lifecycle failed: ${error.runtimeType}.',
          );
          final reservationId = activeReservationId;"""
if old not in s:
    raise SystemExit('failure target not found')
s = s.replace(old, new, 1)

start = s.find('  List<TradeIdea> _rankPrimaryIdeas(List<TradeIdea> ideas) {')
if start < 0:
    raise SystemExit('old rank method not found')
end = s.find('  String _clientId(TradeIdea idea) {', start)
if end < 0:
    raise SystemExit('clientId boundary not found')
helper = """  Future<void> _recordRankingOutcome(
    LocalLiveRankedIdea rankedIdea,
    OpportunityRankingOutcome outcome,
    String reason,
  ) async {
    final ranked = rankedIdea.ranked;
    _rankingJournal.add(
      OpportunityRankingJournalRecord(
        recordedAtUtc: DateTime.now().toUtc(),
        rank: ranked.rank,
        setupId: ranked.candidate.setupId,
        symbol: ranked.candidate.symbol,
        policy: ranked.utility.policy,
        version: ranked.utility.version,
        outcome: outcome,
        reason: reason,
        utilityFingerprint: ranked.utility.fingerprint,
        score: ranked.utility.score,
        componentBreakdown: ranked.utility.componentBreakdown,
        unknownFields: ranked.utility.unknownFields,
      ),
    );
    if (_rankingJournal.length > 500) {
      _rankingJournal.removeRange(0, _rankingJournal.length - 500);
    }
    await _persistState();
  }

"""
s = s[:start] + helper + s[end:]

anchor = """    final pendingClosuresRaw = await FlutterForegroundTask.getData<String>(
      key: localLivePendingJournalClosuresKey,
    );"""
insert = """    final rankingRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveRankingJournalKey,
    );
    if (rankingRaw != null) {
      try {
        final decoded = jsonDecode(rankingRaw);
        if (decoded is List<Object?>) {
          _rankingJournal
            ..clear()
            ..addAll(
              decoded.whereType<Map<Object?, Object?>>().map(
                (item) => OpportunityRankingJournalRecord.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ),
            );
        }
      } on Object {
        _rankingJournal.clear();
      }
    }
""" + anchor
if anchor not in s:
    raise SystemExit('restore anchor not found')
s = s.replace(anchor, insert, 1)

anchor = """  Future<void> _persistState() async {
    await FlutterForegroundTask.saveData(
      key: localLiveManagedPositionsKey,"""
insert = """  Future<void> _persistState() async {
    await FlutterForegroundTask.saveData(
      key: localLiveRankingJournalKey,
      value: jsonEncode(_rankingJournal.map((item) => item.toJson()).toList()),
    );
    await FlutterForegroundTask.saveData(
      key: localLiveManagedPositionsKey,"""
if anchor not in s:
    raise SystemExit('persist anchor not found')
s = s.replace(anchor, insert, 1)

p.write_text(s)
