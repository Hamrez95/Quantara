import 'package:flutter/material.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../application/manual_trade_execution_controller.dart';
import '../domain/manual_trade_execution.dart';

final class ManualTradeExecutionSheet extends StatefulWidget {
  const ManualTradeExecutionSheet({
    required this.controller,
    required this.setup,
    super.key,
  });

  final ManualTradeExecutionController controller;
  final SignalJournalEntry setup;

  @override
  State<ManualTradeExecutionSheet> createState() =>
      _ManualTradeExecutionSheetState();
}

final class _ManualTradeExecutionSheetState
    extends State<ManualTradeExecutionSheet> {
  late final TextEditingController _marginController;
  late int _leverage;
  late int _targetCount;
  bool _editingMargin = false;

  bool get _fa => Directionality.of(context) == TextDirection.rtl;
  String _t(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    final plan = widget.controller.preparation!.plan;
    _marginController = TextEditingController(
      text: plan.margin.toStringAsFixed(2),
    );
    _leverage = plan.leverage;
    _targetCount = plan.targetCount;
  }

  @override
  void dispose() {
    _marginController.dispose();
    super.dispose();
  }

  void _recalculate({bool syncMarginText = false}) {
    final value = double.tryParse(_marginController.text.trim());
    if (value == null) return;
    widget.controller.recalculate(
      margin: value,
      leverage: _leverage,
      targetCount: _targetCount,
    );
    final plan = widget.controller.preparation?.plan;
    if (syncMarginText && plan != null && !_editingMargin) {
      _marginController.text = plan.margin.toStringAsFixed(2);
    }
  }

  Future<void> _reviewAndConfirm() async {
    final preparation = widget.controller.preparation;
    if (preparation == null || !preparation.plan.allowed) return;
    final plan = preparation.plan;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('تأیید نهایی معامله', 'Final trade confirmation')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewLine(label: _t('نماد', 'Symbol'), value: plan.symbol),
              _ReviewLine(
                label: _t('جهت', 'Direction'),
                value: plan.direction == TradeDirection.long
                    ? _t('خرید / Long', 'Long')
                    : _t('فروش / Short', 'Short'),
              ),
              _ReviewLine(
                label: _t('نوع سفارش', 'Order type'),
                value: _t('Market', 'Market'),
              ),
              _ReviewLine(
                label: _t('مارجین', 'Margin'),
                value: _money(plan.margin),
              ),
              _ReviewLine(
                label: _t('اهرم', 'Leverage'),
                value: '${plan.leverage}x',
              ),
              _ReviewLine(
                label: _t('حجم پوزیشن', 'Notional'),
                value: _money(plan.notional),
              ),
              _ReviewLine(
                label: _t('حد ضرر', 'Stop loss'),
                value: _price(plan.stopLoss),
              ),
              _ReviewLine(
                label: _t('حداکثر زیان تخمینی', 'Estimated max loss'),
                value:
                    '${_money(plan.maximumLoss)} · ${plan.riskPercentOfEquity.toStringAsFixed(2)}%',
              ),
              const Divider(height: 24),
              for (var index = 0; index < plan.targetCount; index++)
                _ReviewLine(
                  label: 'TP${index + 1}',
                  value:
                      '${_price(plan.targets[index])} · qty ${plan.targetQuantities[index]}',
                ),
              const SizedBox(height: 12),
              Text(
                _t(
                  'بعد از ثبت Entry + SL + TPها، این قابلیت پوزیشن را خودکار مدیریت نمی‌کند.',
                  'After Entry + SL + TPs are confirmed, this feature will not manage the position automatically.',
                ),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('برگشت', 'Back')),
          ),
          FilledButton.icon(
            key: const Key('manual-trade-final-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.lock_open_rounded),
            label: Text(_t('تأیید و باز کردن معامله', 'Confirm & open trade')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final receipt = await widget.controller.confirmAndExecute();
    if (!mounted) return;
    if (receipt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            widget.controller.error ??
                _t(
                  'معامله برای حفظ ایمنی ارسال نشد.',
                  'The trade was not submitted for safety.',
                ),
          ),
        ),
      );
      return;
    }
    final warning = receipt.warning;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          warning ??
              _t(
                'پوزیشن با حد ضرر و ${receipt.targetOrderIds.length} حد سود در Bitunix تأیید شد.',
                'The position, stop loss and ${receipt.targetOrderIds.length} take-profit order(s) were confirmed on Bitunix.',
              ),
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final preparation = widget.controller.preparation;
        if (preparation == null) {
          return Center(
            child: Text(
              widget.controller.error ??
                  _t(
                    'اطلاعات معامله در دسترس نیست.',
                    'Trade data unavailable.',
                  ),
            ),
          );
        }
        final plan = preparation.plan;
        final maximumLeverage = plan.maximumPermittedLeverage < 1
            ? 1
            : plan.maximumPermittedLeverage;
        final minimumLeverage = preparation.rules.minimumLeverage
            .clamp(1, maximumLeverage)
            .toInt();
        final leverageValue = _leverage
            .clamp(minimumLeverage, maximumLeverage)
            .toInt();

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('باز کردن معامله', 'Open trade'),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.setup.symbol} · ${widget.setup.timeframe} · ${widget.setup.direction == TradeDirection.long ? _t('خرید', 'Long') : _t('فروش', 'Short')}',
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ),
                    if (plan.systemSuggested)
                      Chip(
                        avatar: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                        ),
                        label: Text(_t('پیشنهاد سیستم', 'System suggestion')),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _Panel(
                  title: _t('وضعیت حساب', 'Account'),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      _Metric(
                        label: _t('موجودی قابل استفاده', 'Available'),
                        value: _money(plan.availableMarginBefore),
                      ),
                      _Metric(
                        label: _t('قیمت فعلی', 'Mark price'),
                        value: _price(plan.entryPrice),
                      ),
                      _Metric(
                        label: _t('کیفیت ستاپ', 'Setup quality'),
                        value: '${plan.qualityScore}/100',
                      ),
                      _Metric(
                        label: _t('سقف ریسک', 'Hard risk cap'),
                        value: _money(plan.hardRiskCap),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  title: _t('مدیریت سرمایه', 'Capital management'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('manual-trade-margin'),
                        controller: _marginController,
                        enabled: !widget.controller.isBusy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _t('مارجین ورودی (USDT)', 'Margin (USDT)'),
                          helperText: _t(
                            'حداکثر مجاز فعلی: ${plan.maximumPermittedMargin.toStringAsFixed(2)} USDT',
                            'Current maximum: ${plan.maximumPermittedMargin.toStringAsFixed(2)} USDT',
                          ),
                        ),
                        onTap: () => _editingMargin = true,
                        onChanged: (_) => _recalculate(),
                        onEditingComplete: () {
                          _editingMargin = false;
                          _recalculate(syncMarginText: true);
                          FocusScope.of(context).unfocus();
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        plan.systemSuggested
                            ? _t(
                                'پیشنهاد سیستم: ${(plan.qualityRiskMultiplier * 100).toStringAsFixed(0)}٪ از سقف ریسک این ستاپ، بدون عبور از محدودیت‌های حساب و صرافی.',
                                'System proposal: ${(plan.qualityRiskMultiplier * 100).toStringAsFixed(0)}% of this setup risk cap, without exceeding account or exchange limits.',
                              )
                            : _t(
                                'مقادیر را شما تغییر داده‌اید؛ سقف‌های سخت ریسک و صرافی همچنان اعمال می‌شوند.',
                                'You edited these values; hard risk and exchange limits still apply.',
                              ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_t('اهرم', 'Leverage')}: ${leverageValue}x',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${minimumLeverage}x – ${maximumLeverage}x',
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                      Slider(
                        key: const Key('manual-trade-leverage'),
                        value: leverageValue.toDouble(),
                        min: minimumLeverage.toDouble(),
                        max: maximumLeverage.toDouble(),
                        divisions: maximumLeverage > minimumLeverage
                            ? maximumLeverage - minimumLeverage
                            : null,
                        label: '${leverageValue}x',
                        onChanged: widget.controller.isBusy
                            ? null
                            : (value) {
                                setState(() => _leverage = value.round());
                                _recalculate();
                              },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _t('تعداد حد سود', 'Take-profit count'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        key: const Key('manual-trade-tp-count'),
                        segments: [
                          for (var count = 1; count <= 3; count++)
                            ButtonSegment<int>(
                              value: count,
                              label: Text('$count TP'),
                              enabled: widget.setup.targets.length >= count,
                            ),
                        ],
                        selected: {_targetCount},
                        onSelectionChanged: widget.controller.isBusy
                            ? null
                            : (selection) {
                                setState(() => _targetCount = selection.single);
                                _recalculate();
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  title: _t('خلاصه قبل از ارسال', 'Pre-submit summary'),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      _Metric(
                        label: _t('مارجین', 'Margin'),
                        value:
                            '${_money(plan.margin)} · ${(plan.margin / preparation.account.estimatedEquity * 100).toStringAsFixed(2)}%',
                      ),
                      _Metric(
                        label: _t('حجم پوزیشن', 'Notional'),
                        value: _money(plan.notional),
                      ),
                      _Metric(
                        label: _t('تعداد', 'Quantity'),
                        value: plan.quantity.toString(),
                      ),
                      _Metric(
                        label: _t('حداکثر زیان', 'Max loss'),
                        value:
                            '${_money(plan.maximumLoss)} · ${plan.riskPercentOfEquity.toStringAsFixed(2)}%',
                      ),
                      _Metric(
                        label: _t('هزینه تخمینی', 'Estimated costs'),
                        value: _money(plan.estimatedCosts),
                      ),
                      _Metric(
                        label: _t('مارجین باقی‌مانده', 'Remaining margin'),
                        value: _money(plan.remainingAvailableMargin),
                      ),
                      _Metric(
                        label: _t('حد ضرر', 'Stop loss'),
                        value: _price(plan.stopLoss),
                      ),
                      _Metric(
                        label: _t('لیکوییدیشن', 'Liquidation'),
                        value: _t(
                          'پس از تأیید صرافی',
                          'After exchange confirmation',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  title: _t('تقسیم حد سود', 'Take-profit allocation'),
                  child: Column(
                    children: [
                      for (var index = 0; index < plan.targets.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'TP${index + 1} · ${_price(plan.targets[index])}',
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                              Text(
                                'qty ${plan.targetQuantities.length > index ? plan.targetQuantities[index] : 0}',
                                textDirection: TextDirection.ltr,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (!plan.allowed || widget.controller.error != null) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        widget.controller.error ?? plan.explanation,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('manual-trade-review'),
                  onPressed: plan.allowed && !widget.controller.isBusy
                      ? _reviewAndConfirm
                      : null,
                  icon: widget.controller.isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(
                    widget.controller.isBusy
                        ? _t('در حال بررسی صرافی…', 'Verifying exchange…')
                        : _t('بررسی نهایی', 'Review trade'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _t(
                    'هیچ سفارشی تا قبل از تأیید نهایی شما به صرافی ارسال نمی‌شود. بعد از باز شدن نیز این قابلیت مدیریت خودکار انجام نمی‌دهد.',
                    'No order is sent before your final confirmation. This feature performs no automatic post-entry management.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _money(double value) =>
      QuantaraNumberFormat.marketValue(value, unit: 'USDT');

  String _price(double value) => QuantaraNumberFormat.marketValue(value);
}

final class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 118),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

final class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}
