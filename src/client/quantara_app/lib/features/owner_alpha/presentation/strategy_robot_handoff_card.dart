import 'package:flutter/material.dart';

import '../application/strategy_robot_binding_controller.dart';
import '../domain/owner_alpha_models.dart';
import 'strategy_robot_binding_presentation.dart';

/// Configuration-only Setup → Robot handoff.
///
/// This surface can persist or clear an exact evaluated strategy binding while
/// the runtime is explicitly disarmed. It never arms Local Live, starts a
/// robot, submits an order, or grants exchange authority.
final class StrategyRobotHandoffCard extends StatelessWidget {
  const StrategyRobotHandoffCard({
    super.key,
    required this.controller,
    required this.runtimeState,
    required this.evaluationRunId,
    required this.idea,
    required this.persian,
    this.onOpenRobotSetup,
  });

  final StrategyRobotBindingController controller;
  final StrategyRobotBindingRuntimeState runtimeState;
  final String evaluationRunId;
  final TradeIdea idea;
  final bool persian;
  final VoidCallback? onOpenRobotSetup;

  bool get _canMutate =>
      runtimeState == StrategyRobotBindingRuntimeState.disarmed &&
      !controller.busy;

  String get _candidateSummary {
    final hash = idea.strategySnapshotHash.trim();
    final shortHash = hash.length <= 8 ? hash : '${hash.substring(0, 8)}…';
    return '${idea.registryStrategyId} v${idea.registryStrategyVersion} • '
        '$shortHash • ${idea.symbol}/${idea.timeframe} • $evaluationRunId';
  }

  Future<void> _useInRobot(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          persian ? 'استفاده از همین نسخه در ربات؟' : 'Use this exact version?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _candidateSummary,
              key: const ValueKey('strategy-robot-confirmation-summary'),
            ),
            const SizedBox(height: 12),
            Text(
              persian
                  ? 'این کار فقط نسخه ارزیابی‌شده را به تنظیمات ربات متصل می‌کند و ربات را فعال نمی‌کند.'
                  : 'This only binds the evaluated strategy snapshot to Robot configuration. It does not arm or start execution.',
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('strategy-robot-cancel-action'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(persian ? 'انصراف' : 'Cancel'),
          ),
          FilledButton(
            key: const ValueKey('strategy-robot-confirm-action'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(persian ? 'تأیید اتصال' : 'Confirm binding'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final accepted = await controller.useInRobot(
      evaluationRunId: evaluationRunId,
      idea: idea,
      runtimeState: runtimeState,
    );
    if (!context.mounted) return;
    if (accepted) {
      onOpenRobotSetup?.call();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persian
              ? 'اتصال فقط وقتی ربات صراحتاً Disarmed است و نسخه ارزیابی دقیق معتبر است مجاز است.'
              : 'Binding is allowed only while the robot is explicitly disarmed and the exact evaluated version still resolves.',
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context) async {
    final cleared = await controller.clear(runtimeState: runtimeState);
    if (!context.mounted || cleared) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persian
              ? 'برای پاک‌کردن اتصال، ربات باید صراحتاً Disarmed باشد.'
              : 'The robot must be explicitly disarmed before clearing its strategy binding.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final binding = controller.binding;
        final presentation = binding == null
            ? null
            : StrategyRobotBindingPresentation.fromBinding(binding);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  persian ? 'اتصال Setup به Robot' : 'Setup → Robot',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  presentation == null
                      ? (persian
                            ? 'هنوز هیچ نسخه ارزیابی‌شده‌ای برای ربات انتخاب نشده است.'
                            : 'No evaluated strategy version is selected for the robot yet.')
                      : presentation.robotStatus(persian: persian),
                  key: const ValueKey('strategy-robot-binding-status'),
                ),
                if (presentation != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    presentation.confirmationSummary(persian: persian),
                    key: const ValueKey('strategy-robot-binding-evidence'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('use-in-robot-action'),
                      onPressed: _canMutate ? () => _useInRobot(context) : null,
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(persian ? 'استفاده در ربات' : 'Use in Robot'),
                    ),
                    if (presentation != null)
                      OutlinedButton.icon(
                        key: const ValueKey('clear-robot-binding-action'),
                        onPressed: _canMutate ? () => _clear(context) : null,
                        icon: const Icon(Icons.link_off_rounded),
                        label: Text(
                          persian ? 'پاک‌کردن اتصال' : 'Clear binding',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  persian
                      ? 'این انتخاب فقط پیکربندی را ذخیره می‌کند؛ فعال‌سازی و ورود واقعی همچنان به گیت‌های مستقل Robot و Local Live نیاز دارد.'
                      : 'This stores configuration only. Arming and live entry still require the independent Robot and Local Live safety gates.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
