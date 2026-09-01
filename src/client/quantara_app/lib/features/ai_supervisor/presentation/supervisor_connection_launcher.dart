import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../application/supervisor_connection_controller.dart';
import '../domain/supervisor_connection.dart';
import 'supervisor_connection_panel.dart';

/// Compact, non-blocking entry point for the read-only ChatGPT Supervisor.
///
/// The full connection panel is intentionally shown only on demand. This keeps
/// the trading viewport available to the primary product instead of reserving
/// a large fixed region for an optional operator/developer integration.
final class SupervisorConnectionLauncher extends StatelessWidget {
  const SupervisorConnectionLauncher({required this.controller, super.key});

  final SupervisorConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.snapshot.status;
        final persian = Localizations.localeOf(context).languageCode != 'en';
        final color = _statusColor(status);
        final tooltip = _tooltip(status, persian: persian);

        return Semantics(
          button: true,
          label: tooltip,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton.filledTonal(
                key: const ValueKey('supervisor-compact-launcher'),
                onPressed: () => _open(context),
                tooltip: tooltip,
                icon: const Icon(Icons.smart_toy_rounded),
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
              ),
              PositionedDirectional(
                top: 3,
                end: 3,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('supervisor-status-dot'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final persian =
            Localizations.localeOf(sheetContext).languageCode != 'en';
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SupervisorProvisioningInfo(persian: persian),
                const SizedBox(height: 10),
                SupervisorConnectionPanel(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class _SupervisorProvisioningInfo extends StatelessWidget {
  const _SupervisorProvisioningInfo({required this.persian});

  final bool persian;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuantaraColors.cyan.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: QuantaraColors.cyan.withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: QuantaraColors.cyan,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    persian
                        ? 'این اطلاعات حساب ChatGPT نیستند'
                        : 'These are not ChatGPT account credentials',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              persian
                  ? 'برای استفاده از Supervisor باید بک‌اند Quantara روی یک سرور HTTPS راه‌اندازی شده باشد. Server URL آدرس همان سرور است و Control Token همان راز حداقل ۳۲ کاراکتری است که روی سرور با QUANTARA_CONTROL_TOKEN تنظیم می‌شود.'
                  : 'Supervisor requires a deployed Quantara backend on HTTPS. Server URL is that server origin, and Control Token is the same secret (at least 32 characters) configured on the server as QUANTARA_CONTROL_TOKEN.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              persian
                  ? 'OPENAI_API_KEY فقط روی سرور می‌ماند و نباید داخل اپ وارد شود. اگر چنین سروری را راه‌اندازی نکرده‌ای، فعلاً چیزی برای تنظیم نداری.'
                  : 'OPENAI_API_KEY stays on the server and must never be entered in the app. If you have not deployed such a server, there is nothing to configure here yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(SupervisorConnectionStatus status) => switch (status) {
  SupervisorConnectionStatus.connected => QuantaraColors.success,
  SupervisorConnectionStatus.connecting => QuantaraColors.cyan,
  SupervisorConnectionStatus.notConfigured => QuantaraColors.warning,
  SupervisorConnectionStatus.expired ||
  SupervisorConnectionStatus.revoked ||
  SupervisorConnectionStatus.serverUnreachable ||
  SupervisorConnectionStatus.incompatibleServer => QuantaraColors.danger,
};

String _tooltip(
  SupervisorConnectionStatus status, {
  required bool persian,
}) => switch (status) {
  SupervisorConnectionStatus.connected =>
    persian ? 'ChatGPT Supervisor متصل' : 'ChatGPT Supervisor connected',
  SupervisorConnectionStatus.connecting =>
    persian ? 'در حال بررسی Supervisor' : 'Checking Supervisor',
  SupervisorConnectionStatus.notConfigured => persian
      ? 'تنظیم ChatGPT Supervisor'
      : 'Configure ChatGPT Supervisor',
  _ => persian
      ? 'بررسی اتصال ChatGPT Supervisor'
      : 'Check ChatGPT Supervisor connection',
};
