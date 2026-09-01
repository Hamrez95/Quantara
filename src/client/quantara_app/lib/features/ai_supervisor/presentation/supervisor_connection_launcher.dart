import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../application/supervisor_connection_controller.dart';
import '../domain/supervisor_connection.dart';
import 'supervisor_connection_panel.dart';

/// Keeps the optional AI Supervisor visible without stealing the trading
/// workspace. Full connection/session controls live in an explicit sheet.
class SupervisorConnectionLauncher extends StatelessWidget {
  const SupervisorConnectionLauncher({required this.controller, super.key});

  final SupervisorConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final fa = Directionality.of(context) == TextDirection.rtl;
        final presentation = _presentation(controller.snapshot.status, fa: fa);
        return Semantics(
          button: true,
          label: 'ChatGPT Supervisor. ${presentation.label}',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('supervisor-connection-launcher'),
                onTap: () => _showDetails(context, fa: fa),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 58),
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: presentation.color.withValues(alpha: 0.28),
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: presentation.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.smart_toy_outlined,
                          size: 21,
                          color: presentation.color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ChatGPT Supervisor',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              presentation.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: presentation.color,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('supervisor-open-details'),
                        onPressed: () => _showDetails(context, fa: fa),
                        child: Text(
                          controller.snapshot.status ==
                                  SupervisorConnectionStatus.notConfigured
                              ? (fa ? 'تنظیم' : 'Set up')
                              : (fa ? 'جزئیات' : 'Details'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDetails(BuildContext context, {required bool fa}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.88,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text(
                  fa
                      ? 'اتصال اختیاری Supervisor'
                      : 'Optional Supervisor connection',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                key: const ValueKey('supervisor-setup-explanation'),
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    sheetContext,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  fa
                      ? 'این اتصال فقط برای تحلیل و عیب‌یابی است و برای ترید لازم نیست.\n\n'
                            'Server URL: آدرس HTTPS سرویسی که Quantara.Api / Supervisor روی آن Deploy شده است.\n\n'
                            'Control Token: مقدار QUANTARA_CONTROL_TOKEN همان سرور (حداقل ۳۲ کاراکتر). این مقدار OpenAI API Key یا کلید Bitunix نیست.\n\n'
                            'اگر هنوز Supervisor را روی یک سرور Deploy و تنظیم نکرده‌ای، فعلاً چیزی وارد نکن.'
                      : 'This connection is only for analysis and diagnostics; trading does not depend on it.\n\n'
                            'Server URL: the HTTPS address where Quantara.Api / Supervisor is deployed.\n\n'
                            'Control Token: the QUANTARA_CONTROL_TOKEN configured on that server (at least 32 characters). It is not an OpenAI API key or a Bitunix key.\n\n'
                            'If you have not deployed and configured the Supervisor service yet, leave it unconfigured for now.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 4),
              SupervisorConnectionPanel(controller: controller),
            ],
          ),
        ),
      ),
    );
  }

  static _LauncherPresentation _presentation(
    SupervisorConnectionStatus status, {
    required bool fa,
  }) {
    return switch (status) {
      SupervisorConnectionStatus.notConfigured => _LauncherPresentation(
        fa ? 'تنظیم نشده · اختیاری' : 'Not configured · optional',
        QuantaraColors.warning,
      ),
      SupervisorConnectionStatus.connecting => _LauncherPresentation(
        fa ? 'در حال بررسی اتصال' : 'Checking connection',
        QuantaraColors.warning,
      ),
      SupervisorConnectionStatus.connected => _LauncherPresentation(
        fa ? 'متصل · فقط خواندنی' : 'Connected · read only',
        QuantaraColors.success,
      ),
      SupervisorConnectionStatus.expired => _LauncherPresentation(
        fa ? 'توکن منقضی شده' : 'Token expired',
        QuantaraColors.warning,
      ),
      SupervisorConnectionStatus.revoked => _LauncherPresentation(
        fa ? 'اتصال لغو شده' : 'Connection revoked',
        QuantaraColors.danger,
      ),
      SupervisorConnectionStatus.serverUnreachable => _LauncherPresentation(
        fa ? 'سرور در دسترس نیست' : 'Server unreachable',
        QuantaraColors.warning,
      ),
      SupervisorConnectionStatus.incompatibleServer => _LauncherPresentation(
        fa ? 'سرور ناسازگار' : 'Incompatible server',
        QuantaraColors.danger,
      ),
    };
  }
}

class _LauncherPresentation {
  const _LauncherPresentation(this.label, this.color);

  final String label;
  final Color color;
}
