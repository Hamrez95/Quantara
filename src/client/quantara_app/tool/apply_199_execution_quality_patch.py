from pathlib import Path

api = Path('lib/features/auto_trade/data/bitunix_local_live_api_client.dart')
text = api.read_text(encoding='utf-8')
import_anchor = "import 'bitunix_pnl_mapper.dart';\n"
if "import 'bitunix_order_book_top.dart';" not in text:
    if import_anchor not in text:
        raise SystemExit('api import anchor not found')
    text = text.replace(import_anchor, "import 'bitunix_order_book_top.dart';\n" + import_anchor, 1)
method_anchor = "  Future<BitunixInstrumentRules> fetchInstrumentRules(String symbol) async {\n"
method = """  Future<BitunixOrderBookTop> fetchOrderBookTop(String symbol) async {
    final payload = await _publicGet('/api/v1/futures/market/depth', {
      'symbol': symbol,
      'limit': '1',
    });
    try {
      return BitunixOrderBookTop.fromApiPayload(payload);
    } on FormatException catch (error) {
      throw LocalLiveTradeSafeException(
        'Bitunix order book top was unavailable or malformed: ${error.message}',
      );
    }
  }

"""
if 'Future<BitunixOrderBookTop> fetchOrderBookTop' not in text:
    if method_anchor not in text:
        raise SystemExit('api method anchor not found')
    text = text.replace(method_anchor, method + method_anchor, 1)
api.write_text(text, encoding='utf-8')

service = Path('lib/features/auto_trade/application/local_live_trade_service.dart')
text = service.read_text(encoding='utf-8')
service_import_anchor = "import '../domain/local_live_management_only_after_flat.dart';\n"
if "import '../domain/local_live_no_chase_gate.dart';" not in text:
    if service_import_anchor not in text:
        raise SystemExit('service import anchor not found')
    text = text.replace(
        service_import_anchor,
        service_import_anchor + "import '../domain/local_live_no_chase_gate.dart';\n",
        1,
    )
entry_anchor = """        final markPrice = await exchange.fetchMarkPrice(idea.symbol);
        final rules = await exchange.fetchInstrumentRules(idea.symbol);
        final canonical = evaluateLocalLiveCanonicalDecision(
"""
entry_replacement = """        final markPrice = await exchange.fetchMarkPrice(idea.symbol);
        final rules = await exchange.fetchInstrumentRules(idea.symbol);
        final topOfBook = await exchange.fetchOrderBookTop(idea.symbol);
        final noChase = const LocalLiveNoChaseGate().evaluate(
          idea: idea,
          topOfBook: topOfBook,
          evaluatedAtUtc: DateTime.now().toUtc(),
        );
        if (!noChase.allowed) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.canonicalRejected,
            'Live no-chase gate rejected executable price: ${noChase.reason.name}.',
          );
          _auditEvent(
            'no_chase_block',
            'Executable top-of-book price failed the no-chase policy: ${noChase.reason.name}.',
            symbol: idea.symbol,
          );
          continue;
        }
        final canonical = evaluateLocalLiveCanonicalDecision(
"""
if 'final topOfBook = await exchange.fetchOrderBookTop(idea.symbol);' not in text:
    if entry_anchor not in text:
        raise SystemExit('service entry anchor not found')
    text = text.replace(entry_anchor, entry_replacement, 1)
service.write_text(text, encoding='utf-8')
