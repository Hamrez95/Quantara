import 'package:flutter/material.dart';

import '../application/local_live_execution_mode_controller.dart';
import '../domain/local_live_execution_mode.dart';

final class LocalLiveExecutionModeSelector extends StatelessWidget {
  const LocalLiveExecutionModeSelector({
    required this.controller,
    required this.tradingIsRunning,
    required this.isPersian,
    super.key,
  });

  final LocalLiveExecutionModeController controller;
  final bool tradingIsRunning;
  final bool isPersian;

  String _t(String fa, String en) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('حالت اجرای سفارش', 'Order execution mode'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SegmentedButton<LocalLiveExecutionMode>(
              showSelectedIcon: true,
              multiSelectionEnabled: false,
              emptySelectionAllowed: false,
              segments: [
                ButtonSegment(
                  value: LocalLiveExecutionMode.readOnly,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(_t('فقط مشاهده', 'Read only')),
                ),
                ButtonSegment(
                  value: LocalLiveExecutionMode.approvalRequired,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(_t('با تأیید من', 'Ask approval')),
                ),
                ButtonSegment(
                  value: LocalLiveExecutionMode.guardedAuto,
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: Text(_t('اتوماتیک', 'Guarded auto')),
                ),
              ],
              selected: {controller.mode},
              onSelectionChanged: controller.isBusy || tradingIsRunning
                  ? null
                  : (selection) => _select(context, selection.single),
            ),
            const SizedBox(height: 8),
            Text(
              switch (controller.mode) {
                LocalLiveExecutionMode.readOnly => _t(
                  'حساب و موقعیت‌ها دیده می‌شوند، اما هیچ سفارش ورودی ارسال نمی‌شود.',
                  'Account data is visible, but no entry order can be submitted.',
                ),
                LocalLiveExecutionMode.approvalRequired => _t(
                  'موقعیت مناسب ابتدا به شکل پیشنهاد نمایش داده می‌شود و بدون تأیید تو اجرا نمی‌شود.',
                  'Eligible setups become proposals and cannot execute without your approval.',
                ),
                LocalLiveExecutionMode.guardedAuto => _t(
                  'بعد از Start، موقعیت واجد شرایط بدون تأیید جداگانه و فقط در محدوده ریسک اجرا می‌شود.',
                  'After Start, eligible setups execute without per-trade approval and only inside risk limits.',
                ),
              },
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 6),
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _select(
    BuildContext context,
    LocalLiveExecutionMode next,
  ) async {
    var accepted = true;
    if (next == LocalLiveExecutionMode.guardedAuto) {
      accepted =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: Text(_t('فعال‌سازی حالت خودکار', 'Enable Guarded Auto')),
              content: Text(
                _t(
                  'بعد از زدن Start، هر موقعیت واجد شرایط بدون اجازه جداگانه باز می‌شود. محدودیت ریسک، تعداد پوزیشن، SL تأییدشده و مدار ایمنی همچنان اجباری هستند.',
                  'After Start, eligible setups can open without another confirmation. Risk limits, position caps, verified SL, and circuit breakers remain mandatory.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(_t('لغو', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(_t('متوجه شدم', 'I understand')),
                ),
              ],
            ),
          ) ??
          false;
    }
    await controller.select(
      next,
      tradingIsRunning: tradingIsRunning,
      autoModeWarningAccepted: accepted,
    );
  }
}
