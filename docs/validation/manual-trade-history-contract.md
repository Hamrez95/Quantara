# Manual account history and simulated setup outcomes

## Verified scope

The owner diagnostic from 2026-10-04 reported a fresh, connected, flat account with an unresolved historical trade. The bundle did not contain exchange rows or candle history, so overlapping HEDGE attribution is a reproduced failure class, not a proven reconstruction of that particular exchange trade.

Changes:
- Recover ambiguous trade attribution with Bitunix position-filtered history; compare immutable trade economics, reject conflicting identities, and retain fail-closed behavior on incomplete or inconsistent responses.
- Reuse the same complete account reconciler in both private account paths. The former secondary path read only the first 100 history rows.
- Keep attribution caches isolated across API credentials. Reuse successfully established immutable mappings without repeating scoped REST queries.
- Paper replay consumes closed candles only and never reuses a TP candle against the stop raised after that candle. Repeated scans are idempotent at that event boundary.
- Export all locally retained setup records, versions, parameters, entry/stop/targets and simulated outcomes; include exchange accounting when available. Notes and credentials are excluded. TP1/TP2 are not counted as completed trades in export summaries. A profitable protected runner stop is not colored as a loss.
- Existing terminal paper outcomes are preserved, not rewritten without archived candles. Export explicitly identifies this legacy evidence limit.

## Regression evidence

`bitunix_history_attribution_test.dart`: a flat account with overlapping XRP position intervals and trades without positionId becomes risk-ready only after two exchange-filtered responses establish unique identity. A second unchanged refresh performs zero extra scoped requests. Different credentials require fresh mappings. Duplicate identities, differing economics and truncation remain blocked. No mutation requests occur.

`signal_outcome_evaluator_test.dart`: repeating the TP1 candle leaves TP1 unchanged; an unfinished candle cannot permanently stop a setup; a stop touch without entry touch is not a trade. Existing stop-first policy for genuinely ambiguous OHLC ordering remains conservative.

`trading_evidence_export_test.dart`: terminal net returns are counted separately from interim target marks and notes are absent.

## Exchange contract references

Checked official documentation:
- https://www.bitunix.com/api-docs/futures/trade/get_history_trades.html — positionId query, optional symbol, skip, maximum limit 100; response documents tradeId/orderId but does not guarantee positionId.
- https://www.bitunix.com/api-docs/futures/position/get_history_positions.html — positionId, create/modify timestamps, fee/funding, gross realizedPNL.
- https://www.bitunix.com/api-docs/futures/trade/place_order.html — HEDGE OPEN direction, clientId, exchange-native SL/TP parameters.

Explicit user confirmation, fresh account reconciliation, sizing/exchange rules, isolated margin, new-position protection and ambiguous submission persistence remain required. Automatic trading stays disabled. Withdrawals, transfers, cross-margin expansion and LLM mutation authority remain outside product scope.

## Strategy evidence and research boundary

The owner's reported losses concern simulated setup outcomes, not executed Bitunix trades. Correcting replay bookkeeping is necessary before interpreting strategy stop rates. It is not evidence that signal profitability improved.

Research references:
- Bailey, Borwein, Lopez de Prado and Zhu, The Probability of Backtest Overfitting: https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf
- Marcos Lopez de Prado, Advances in Financial Machine Learning, publisher overview: https://www.wiley-vch.de/en?isbn=9781119482086&option=com_eshop&view=product

Use chronological untouched test data, walk-forward validation, realistic fees/spread/slippage/funding, parameter sensitivity and a complete ledger before promoting new parameters. Existing quality gates already require these. Book or paper descriptions alone do not justify replacing the production strategies. This slice changes replay correctness, not strategy thresholds. Exported setup history and archived market candles are still required to attribute the owner's observed stop-outs or tune strategies without guessing.

## Galaxy A55 acceptance

1. Update in place; connect Bitunix and refresh a flat account with overlapping historical trades.
2. Open a fresh complete setup. Confirm that a sizing/confirmation sheet opens. Cancel first to verify no order occurs before confirmation.
3. Export setup history and failed-preflight diagnostics; open both JSON files and confirm their financial evidence and absence of credentials.
4. Repeat scans after TP1 and inspect unchanged result until a later closed candle produces a new event.
5. Test disconnection, stale public data and ambiguous previous submission: entries must stay blocked with a reason.

Physical exchange execution, real-device frame timings and long-session behavior are not established by CI fixtures.

Rollback: revert this code slice and retain installed app data. Do not delete ambiguous execution records or retry real orders. Existing exchange-native protection remains authoritative; re-run account reconciliation after any rollback. Production/store publication remains a separate decision.
