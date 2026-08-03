import 'dart:async';

import 'package:flutter/material.dart';

import '../application/portfolio_risk_simulation_controller.dart';
import '../domain/portfolio_risk_models.dart';

final class PortfolioRiskPanel extends StatefulWidget {
  const PortfolioRiskPanel({super.key, this.controller});

  final PortfolioRiskSimulationController? controller;

  @override
  State<PortfolioRiskPanel> createState() => _PortfolioRiskPanelState();
}

final class _PortfolioRiskPanelState extends State<PortfolioRiskPanel> {
  late final PortfolioRiskSimulationController _controller =
      widget.controller ?? PortfolioRiskSimulationController();
  late final bool _ownsController = widget.controller == null;

  bool get _fa => Directionality.of(context) == TextDirection.rtl;
  String _t(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 12),
                _safetyNotice(),
                if (_controller.error != null) ...[
                  const SizedBox(height: 12),
                  _messageBox(
                    icon: Icons.error_outline_rounded,
                    text: _t(
                      'خواندن دفتر ریسک ناموفق بود؛ ورود جدید مسدود می‌ماند.',
                      'The risk ledger could not be read; new entries remain blocked.',
                    ),
                    tone: Theme.of(context).colorScheme.error,
                  ),
                ],
                if (_controller.loading && snapshot == null) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                ] else if (snapshot != null) ...[
                  const SizedBox(height: 16),
                  _budgetGrid(snapshot),
                  const SizedBox(height: 16),
                  _status(snapshot),
                  const SizedBox(height: 16),
                  _simulationActions(),
                  const SizedBox(height: 16),
                  _positions(snapshot),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.account_balance_wallet_outlined),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('بودجه ریسک پرتفوی', 'Portfolio risk budget'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _t(
                'ظرفیت هم‌زمان بر اساس ریسک روزانه و مارجین آزاد، نه تعداد ثابت پوزیشن',
                'Concurrent capacity is based on daily risk and free margin, not a fixed position count.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Chip(
        avatar: const Icon(Icons.science_outlined, size: 18),
        label: Text(_t('شبیه‌سازی', 'Simulation')),
      ),
    ],
  );

  Widget _safetyNotice() => _messageBox(
    icon: Icons.lock_outline_rounded,
    text: _t(
      'ورود واقعی در این نسخه سخت‌افزاری غیرفعال است. این پنل فقط تصمیم، رزرو و بازیابی بودجه را شبیه‌سازی می‌کند و هیچ سفارش واقعی را تغییر نمی‌دهد.',
      'Real entry is hard-disabled in this build. This panel only simulates decisions, reservations, and recovery; it cannot mutate exchange orders.',
    ),
    tone: Theme.of(context).colorScheme.primary,
  );

  Widget _budgetGrid(PortfolioRiskSnapshot snapshot) {
    final risk = snapshot.dailyRisk;
    final margin = snapshot.margin;
    final items = <({String label, String value})>[
      (
        label: _t('سقف ریسک روزانه', 'Daily risk limit'),
        value: _money(risk.limit),
      ),
      (
        label: _t('ضرر محقق‌شده', 'Realized loss'),
        value: _money(risk.realizedLoss),
      ),
      (
        label: _t('ریسک پوزیشن باز', 'Open risk'),
        value: _money(risk.openRisk),
      ),
      (
        label: _t('ریسک Pending', 'Pending risk'),
        value: _money(risk.pendingRisk),
      ),
      (
        label: _t('ریسک مبهم', 'Ambiguous risk'),
        value: _money(risk.ambiguousRisk),
      ),
      (
        label: _t('ریسک باقی‌مانده', 'Available risk'),
        value: _money(risk.available),
      ),
      (
        label: _t('مارجین استفاده‌شده', 'Used margin'),
        value: _money(margin.usedMargin),
      ),
      (
        label: _t('مارجین رزرو', 'Reserved margin'),
        value: _money(margin.reservedMargin),
      ),
      (
        label: _t('مارجین آزاد', 'Free margin'),
        value: _money(margin.freeMargin),
      ),
      (
        label: _t('بافر ایمنی', 'Safety buffer'),
        value: _money(margin.safetyBuffer),
      ),
      (
        label: _t('ظرفیت مارجین', 'Spendable margin'),
        value: _money(margin.spendable),
      ),
      (
        label: _t('پوزیشن باز', 'Open positions'),
        value: snapshot.openPositionCount.toString(),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 3
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 82),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.value,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _status(PortfolioRiskSnapshot snapshot) {
    final blocked = snapshot.blockReason != PortfolioEntryBlockReason.none;
    final last = _controller.lastDecision;
    final decisionText = last == null
        ? _t(
            'برای نمونه ابتدا ۳ دلار و سپس ۴ دلار رزرو کن؛ از سقف ۱۰ دلار، ۳ دلار باقی می‌ماند.',
            'Reserve 3 USDT and then 4 USDT; 3 USDT remains from the 10 USDT limit.',
          )
        : last.allowed
        ? _t(
            'رزرو پذیرفته شد؛ ریسک باقی‌مانده ${_money(last.availableRiskAfter)} است.',
            'Reservation accepted; remaining risk is ${_money(last.availableRiskAfter)}.',
          )
        : _blockLabel(last.reason);
    return _messageBox(
      icon: blocked || (last != null && !last.allowed)
          ? Icons.block_rounded
          : Icons.verified_user_outlined,
      text: blocked ? _blockLabel(snapshot.blockReason) : decisionText,
      tone: blocked || (last != null && !last.allowed)
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.tertiary,
    );
  }

  Widget _simulationActions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton.tonalIcon(
        onPressed: _controller.loading
            ? null
            : () => _controller.reserveExample(3),
        icon: const Icon(Icons.add_chart_rounded),
        label: Text(_t('رزرو ۳ USDT', 'Reserve 3 USDT')),
      ),
      FilledButton.tonalIcon(
        onPressed: _controller.loading
            ? null
            : () => _controller.reserveExample(4),
        icon: const Icon(Icons.add_chart_rounded),
        label: Text(_t('رزرو ۴ USDT', 'Reserve 4 USDT')),
      ),
      OutlinedButton.icon(
        onPressed: _controller.loading
            ? null
            : () => _controller.reserveExample(8),
        icon: const Icon(Icons.rule_rounded),
        label: Text(_t('آزمون Reject با ۸', 'Try rejected 8')),
      ),
      OutlinedButton.icon(
        onPressed: _controller.loading ? null : _controller.toggleFreshness,
        icon: Icon(
          _controller.accountFresh
              ? Icons.cloud_off_outlined
              : Icons.cloud_done_outlined,
        ),
        label: Text(
          _controller.accountFresh
              ? _t('شبیه‌سازی داده Stale', 'Simulate stale data')
              : _t('بازگردانی داده Fresh', 'Restore fresh data'),
        ),
      ),
      TextButton.icon(
        onPressed: _controller.loading ? null : _controller.reset,
        icon: const Icon(Icons.restart_alt_rounded),
        label: Text(_t('بازنشانی مثال', 'Reset example')),
      ),
    ],
  );

  Widget _positions(PortfolioRiskSnapshot snapshot) {
    if (snapshot.positions.isEmpty) {
      return _messageBox(
        icon: Icons.inbox_outlined,
        text: _t(
          'هنوز Reservation فعالی وجود ندارد.',
          'There are no active reservations yet.',
        ),
        tone: Theme.of(context).colorScheme.outline,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('Reservationهای فعال', 'Active reservations'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final position in snapshot.positions) ...[
          _positionTile(position, snapshot.dailyRisk.limit),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _positionTile(PositionRiskReservation position, double dailyLimit) {
    final riskPercent = dailyLimit <= 0
        ? 0
        : position.maximumLoss / dailyLimit * 100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                position.symbol,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              Chip(
                label: Text(
                  position.side == PortfolioSide.long ? 'LONG' : 'SHORT',
                ),
              ),
              Chip(label: Text(position.lifecycle.name)),
              Chip(label: Text(position.verification.name)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _fact(_t('ورود', 'Entry'), position.entryPrice.toStringAsFixed(4)),
              _fact(
                _t('استاپ تأییدشده', 'Confirmed stop'),
                position.currentExchangeConfirmedStop.toStringAsFixed(4),
              ),
              _fact(
                _t('تعداد', 'Quantity'),
                position.plannedQuantity.toStringAsFixed(4),
              ),
              _fact(_t('حداکثر زیان', 'Maximum loss'), _money(position.maximumLoss)),
              _fact(_t('مارجین', 'Margin'), _money(position.reservedMargin)),
              _fact(
                _t('سهم از سقف', 'Daily limit share'),
                '${riskPercent.toStringAsFixed(1)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$label: '),
        TextSpan(
          text: value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _messageBox({
    required IconData icon,
    required String text,
    required Color tone,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.10),
      border: Border.all(color: tone.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tone),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );

  String _blockLabel(PortfolioEntryBlockReason reason) => switch (reason) {
    PortfolioEntryBlockReason.none => _t('مجاز', 'Allowed'),
    PortfolioEntryBlockReason.invalidInput =>
      _t('ورودی قیمت، تعداد، استاپ یا مارجین نامعتبر است.', 'Price, quantity, stop, or margin input is invalid.'),
    PortfolioEntryBlockReason.staleAccount =>
      _t('داده خصوصی حساب Stale است؛ Entry جدید مسدود شد.', 'Private account truth is stale; new entry is blocked.'),
    PortfolioEntryBlockReason.incompleteProtection =>
      _t('حداقل یک پوزیشن Protection تأییدشده ندارد.', 'At least one position lacks verified protection.'),
    PortfolioEntryBlockReason.unsupportedMarginMode =>
      _t('فقط Isolated Margin مجاز است.', 'Only isolated margin is allowed.'),
    PortfolioEntryBlockReason.duplicateCandidate =>
      _t('Candidate یا Trade تکراری است.', 'The candidate or trade is duplicated.'),
    PortfolioEntryBlockReason.sameSymbolOverlap =>
      _t('هم‌پوشانی روی یک Symbol در سیاست محافظه‌کارانه مسدود است.', 'Same-symbol overlap is blocked by the conservative policy.'),
    PortfolioEntryBlockReason.ambiguousReservation =>
      _t('Reservation مبهم تا Reconciliation ظرفیت را قفل کرده است.', 'An ambiguous reservation locks capacity until reconciliation.'),
    PortfolioEntryBlockReason.emergencyTechnicalCeiling =>
      _t('سقف فنی اضطراری فعال شده است.', 'The emergency technical ceiling was reached.'),
    PortfolioEntryBlockReason.exchangeMinimum =>
      _t('حداقل Quantity یا Notional صرافی رعایت نشده است.', 'The exchange minimum quantity or notional is not met.'),
    PortfolioEntryBlockReason.riskBudgetInsufficient =>
      _t('بودجه ریسک باقی‌مانده کافی نیست.', 'The remaining risk budget is insufficient.'),
    PortfolioEntryBlockReason.marginInsufficient =>
      _t('مارجین آزاد پس از بافر ایمنی کافی نیست.', 'Free margin is insufficient after the safety buffer.'),
    PortfolioEntryBlockReason.directionConcentration =>
      _t('تمرکز ریسک در یک جهت از سقف محافظه‌کارانه عبور می‌کند.', 'Directional risk concentration exceeds the conservative cap.'),
  };

  String _money(double value) => '${value.toStringAsFixed(2)} USDT';
}
