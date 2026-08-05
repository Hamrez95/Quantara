from pathlib import Path

SERVICE = Path(
    "src/client/quantara_app/lib/features/auto_trade/application/"
    "local_live_trade_service.dart"
)
TEST = Path(
    "src/client/quantara_app/test/"
    "local_live_multi_position_service_source_test.dart"
)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


service = SERVICE.read_text(encoding="utf-8")

old_intro = """      final idea = _pickPrimaryIdea(ideas);
      if (idea == null) {
        _auditEvent(
          'scan_skip',
          'Actionable setups were skipped because selected timeframes disagreed on direction.',
        );
        return;
      }
"""
new_intro = """      final rankedIdeas = _rankPrimaryIdeas(ideas);
      if (rankedIdeas.isEmpty) {
        _auditEvent(
          'scan_skip',
          'Actionable setups were skipped because selected timeframes disagreed on direction.',
        );
        return;
      }
      for (final idea in rankedIdeas) {
"""
service = replace_once(service, old_intro, new_intro, "ranked candidate loop")

loop_start = service.index("      for (final idea in rankedIdeas) {")
reservation_marker = service.index(
    "      String? activeReservationId = 'local-live:${idea.setupId}';",
    loop_start,
)
pre_order = service[loop_start:reservation_marker]
if "        return;" not in pre_order:
    raise RuntimeError("candidate skip returns were not found")
pre_order = pre_order.replace("        return;", "        continue;")
service = service[:loop_start] + pre_order + service[reservation_marker:]

success_tail = """          symbol: idea.symbol,
        );
      } on Object catch (error) {
"""
service = replace_once(
    service,
    success_tail,
    """          symbol: idea.symbol,
        );
        return;
      } on Object catch (error) {
""",
    "single successful entry per cycle",
)

outer_finally = """    } finally {
      client.close();
    }
  }

  Future<void> _recoverVerifiedQuantaraOrphans(
"""
service = replace_once(
    service,
    outer_finally,
    """      }
      _auditEvent(
        'scan_candidates_exhausted',
        'All ranked actionable setups were evaluated, but none passed every entry gate.',
      );
    } finally {
      client.close();
    }
  }

  Future<void> _recoverVerifiedQuantaraOrphans(
""",
    "candidate exhaustion audit and loop close",
)

service = replace_once(
    service,
    "  TradeIdea? _pickPrimaryIdea(List<TradeIdea> ideas) {",
    "  List<TradeIdea> _rankPrimaryIdeas(List<TradeIdea> ideas) {",
    "rank helper signature",
)
service = replace_once(
    service,
    """    return candidates.firstOrNull;
  }

  String _clientId(TradeIdea idea) {
""",
    """    return List.unmodifiable(candidates);
  }

  String _clientId(TradeIdea idea) {
""",
    "rank helper return",
)

SERVICE.write_text(service, encoding="utf-8")

test = TEST.read_text(encoding="utf-8")
marker = """}

LocalLiveTradeConfiguration _configuration(int maximum) =>
"""
new_test = """  test('blocked top-ranked setup cannot starve lower-ranked symbols', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(source, contains('final rankedIdeas = _rankPrimaryIdeas(ideas);'));
    expect(source, contains('for (final idea in rankedIdeas)'));
    expect(source, contains('List<TradeIdea> _rankPrimaryIdeas'));
    expect(source, contains("'scan_candidates_exhausted'"));

    final reservationBlock = source.indexOf("'portfolio_reservation_block'");
    final nextCandidate = source.indexOf('continue;', reservationBlock);
    expect(reservationBlock, greaterThanOrEqualTo(0));
    expect(nextCandidate, greaterThan(reservationBlock));

    final protected = source.indexOf("'position_protected'");
    final successfulReturn = source.indexOf('return;', protected);
    expect(protected, greaterThanOrEqualTo(0));
    expect(successfulReturn, greaterThan(protected));
  });
}

LocalLiveTradeConfiguration _configuration(int maximum) =>
"""
test = replace_once(test, marker, new_test, "candidate starvation regression test")
TEST.write_text(test, encoding="utf-8")
