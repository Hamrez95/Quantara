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

    final status = switch (state.health) {
      PrivateAccountReconciliationHealth.unavailable =>
        persian ? 'ناموجود' : 'unavailable',
      PrivateAccountReconciliationHealth.fresh => persian ? 'تازه' : 'fresh',
      PrivateAccountReconciliationHealth.stale => persian ? 'قدیمی' : 'stale',
      PrivateAccountReconciliationHealth.divergent =>
        persian ? 'متناقض' : 'divergent',
    };
    final lastSnapshot = state.snapshot?.syncedAt.toLocal().toString() ?? '—';
    final message = persian
        ? 'وضعیت خصوصی حساب $status است. ورود جدید بسته شده، اما مدیریت پوزیشن موجود ادامه دارد. آخرین Snapshot: $lastSnapshot'
        : 'Private account truth is $status. New entries are blocked while existing-position management continues. Last snapshot: $lastSnapshot';
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.error.withValues(alpha: 0.42)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sync_problem_rounded, color: colors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
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
