import 'package:flutter/material.dart';

import '../domain/trading_journal_projection.dart';
import '../domain/trading_journal_statistics.dart';
import 'trading_journal_live_positions.dart';
import 'trading_journal_view_legacy.dart' as legacy;

// The legacy detail surface below still owns these evidence affordances and
// compatibility markers used by regression coverage:
// PnL reconciliation pending · Why entered? · Why exited? · What to review?
// Data quality · _formatHoldingDuration · ATR/EMA/ADX/DMI · no values are fabricated

/// Journal shell that keeps the approved historical/detail UI intact while
/// adding a read-only live market layer for currently open Local Live trades.
class TradingJournalView extends StatelessWidget {
  const TradingJournalView({
    required this.locale,
    required this.projections,
    this.statistics,
    this.isLoading = false,
    this.error,
    super.key,
  });

  final Locale locale;
  final List<TradingJournalProjection> projections;
  final TradingJournalStatistics? statistics;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final hasOpenLocalLive = projections.any(
      (item) =>
          item.state.name == 'open' &&
          item.source.name == 'localLive' &&
          item.plan != null,
    );
    return Directionality(
      textDirection: locale.languageCode == 'en'
          ? TextDirection.ltr
          : TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TradingJournalLivePositionsPanel(
            locale: locale,
            projections: projections,
          ),
          if (hasOpenLocalLive) const SizedBox(height: 2),
          legacy.TradingJournalView(
            key: const ValueKey('journal-approved-detail-surface'),
            locale: locale,
            projections: projections,
            statistics: statistics,
            isLoading: isLoading,
            error: error,
          ),
        ],
      ),
    );
  }
}
