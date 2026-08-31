import 'package:flutter/material.dart';

import '../domain/private_account_reconciliation.dart';

final class PrivateAccountReconciliationBanner extends StatelessWidget {
  const PrivateAccountReconciliationBanner({
    required this.state,
    required this.persian,
    super.key,
  });

  final PrivateAccountReconciliationState state;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    if (state.health == PrivateAccountReconciliationHealth.fresh) {
      return const SizedBox.shrink();
    }

    final snapshotOpenCount = state.snapshot?.positions.length;
    final localLiveOpenCount = state.localLiveOpenPositionCount;
    final confirmedOpenCount = switch ((
      snapshotOpenCount,
      localLiveOpenCount,
    )) {
      (final int snapshotCount, final int localCount)
          when snapshotCount > 0 || localCount > 0 =>
        snapshotCount > localCount ? snapshotCount : localCount,
      (final int snapshotCount, _) => snapshotCount,
      (_, final int localCount) => localCount,
      _ => null,
    };
    final hasConfirmedOpenPosition = (confirmedOpenCount ?? 0) > 0;
    final isDivergent =
        state.health == PrivateAccountReconciliationHealth.divergent;
    final severe = isDivergent || hasConfirmedOpenPosition;
    final status = switch (state.health) {
      PrivateAccountReconciliationHealth.unavailable =>
        persian ? 'ناموجود' : 'unavailable',
      PrivateAccountReconciliationHealth.fresh => persian ? 'تازه' : 'fresh',
      PrivateAccountReconciliationHealth.stale => persian ? 'قدیمی' : 'stale',
      PrivateAccountReconciliationHealth.divergent =>
        persian ? 'متناقض' : 'divergent',
    };
    final lastSnapshot = state.snapshot?.syncedAt.toLocal().toString() ?? '—';
    final refreshState = state.refreshing
        ? (persian ? 'در حال تازه‌سازی' : 'refreshing')
        : (persian ? 'منتظر تازه‌سازی' : 'waiting for refresh');

    final message = switch ((isDivergent, hasConfirmedOpenPosition, persian)) {
      (true, _, true) =>
        'اطلاعات حساب با وضعیت Local Live متناقض است. ورود جدید تا رفع این اختلاف متوقف می‌ماند. آخرین Snapshot: $lastSnapshot · $refreshState',
      (true, _, false) =>
        'Account information disagrees with Local Live. New entries stay paused until the mismatch is reconciled. Last snapshot: $lastSnapshot · $refreshState',
      (false, true, true) =>
        'وضعیت خصوصی حساب $status است. ورود جدید بسته است و فقط حفاظت یا کاهش ریسک پوزیشن موجود می‌تواند ادامه پیدا کند. آخرین Snapshot: $lastSnapshot · $refreshState',
      (false, true, false) =>
        'Private account truth is $status. New entries are blocked; only protection or risk-reducing management of confirmed open positions may continue. Last snapshot: $lastSnapshot · $refreshState',
      (false, false, true) =>
        'اطلاعات حساب نیاز به تازه‌سازی دارد. هیچ پوزیشن بازی در آخرین وضعیت تاییدشده شناخته نشده است. ورود جدید تا موفق‌شدن تازه‌سازی صرافی متوقف می‌ماند. آخرین Snapshot: $lastSnapshot · $refreshState',
      (false, false, false) =>
        'Account information needs refresh. No open position is known in the latest confirmed state. New entries are paused until the exchange account refresh succeeds. Last snapshot: $lastSnapshot · $refreshState',
    };
    final colors = Theme.of(context).colorScheme;
    final background = severe
        ? colors.errorContainer.withValues(alpha: 0.68)
        : colors.tertiaryContainer.withValues(alpha: 0.72);
    final border = severe
        ? colors.error.withValues(alpha: 0.42)
        : colors.tertiary.withValues(alpha: 0.42);
    final foreground = severe
        ? colors.onErrorContainer
        : colors.onTertiaryContainer;
    final iconColor = severe ? colors.error : colors.tertiary;

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                severe ? Icons.sync_problem_rounded : Icons.sync_rounded,
                color: iconColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
