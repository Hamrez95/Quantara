import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../application/supervisor_connection_controller.dart';
import '../application/supervisor_read_only_session_controller.dart';
import '../domain/supervisor_connection.dart';
import '../domain/supervisor_read_only_session.dart';

class SupervisorConnectionPanel extends StatefulWidget {
  const SupervisorConnectionPanel({required this.controller, super.key});

  final SupervisorConnectionController controller;

  @override
  State<SupervisorConnectionPanel> createState() =>
      _SupervisorConnectionPanelState();
}

class _SupervisorConnectionPanelState extends State<SupervisorConnectionPanel> {
  static const _sessionDuration = Duration(minutes: 15);

  late final SupervisorReadOnlySessionController _sessionController =
      SupervisorReadOnlySessionController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_enforceConnectionBoundSession);
  }

  @override
  void didUpdateWidget(covariant SupervisorConnectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_enforceConnectionBoundSession);
    widget.controller.addListener(_enforceConnectionBoundSession);
    _enforceConnectionBoundSession();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_enforceConnectionBoundSession);
    _sessionController.dispose();
    super.dispose();
  }

  void _enforceConnectionBoundSession() {
    if (_sessionController.isActive &&
        widget.controller.snapshot.status !=
            SupervisorConnectionStatus.connected) {
      _sessionController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _sessionController]),
      builder: (context, _) {
        final fa = Directionality.of(context) == TextDirection.rtl;
        final snapshot = widget.controller.snapshot;
        final presentation = _presentation(snapshot.status, fa: fa);
        return Semantics(
          container: true,
          label: '${presentation.title}. ${presentation.summary}',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: SingleChildScrollView(
                child: SectionCard(
                  accentColor: presentation.color,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: presentation.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.smart_toy_outlined,
                              color: presentation.color,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fa
                                      ? 'ChatGPT Supervisor · فقط خواندنی'
                                      : 'ChatGPT Supervisor · Read only',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 2),
                                Text(presentation.summary),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: fa
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: StatusPill(
                          label: presentation.title,
                          color: presentation.color,
                          icon: presentation.icon,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        fa
                            ? 'این اتصال فقط برای تحلیل و عیب‌یابی محدود است. کلید/Secret صرافی، سفارش، SL/TP، اهرم، انتقال وجه و اختیار اجرای معامله به ChatGPT داده نمی‌شود.'
                            : 'This connection is limited to analysis and diagnostics. Exchange credentials, orders, SL/TP, leverage, funds transfers, and trading execution authority are never granted to ChatGPT.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (snapshot.serverOrigin != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          snapshot.serverOrigin!.host,
                          key: const ValueKey('supervisor-server-origin'),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                      if (snapshot.lastSuccessfulHealthCheckAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          fa
                              ? 'آخرین سلامت موفق: ${snapshot.lastSuccessfulHealthCheckAt!.toLocal()}'
                              : 'Last healthy check: ${snapshot.lastSuccessfulHealthCheckAt!.toLocal()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (snapshot.diagnosticCode != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${fa ? 'کد عیب‌یابی' : 'Diagnostic code'}: ${snapshot.diagnosticCode}',
                          key: const ValueKey('supervisor-diagnostic-code'),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 10),
                      _buildSessionControls(context, snapshot.status, fa: fa),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                snapshot.status ==
                                    SupervisorConnectionStatus.connecting
                                ? null
                                : () => _showSetupDialog(context, fa: fa),
                            icon: const Icon(Icons.settings_outlined),
                            label: Text(
                              snapshot.status ==
                                      SupervisorConnectionStatus.notConfigured
                                  ? (fa ? 'تنظیم اتصال' : 'Configure')
                                  : (fa ? 'ویرایش اتصال' : 'Update setup'),
                            ),
                          ),
                          if (snapshot.status !=
                              SupervisorConnectionStatus.notConfigured)
                            OutlinedButton.icon(
                              onPressed:
                                  snapshot.status ==
                                      SupervisorConnectionStatus.connecting
                                  ? null
                                  : () =>
                                        unawaited(widget.controller.checkNow()),
                              icon:
                                  snapshot.status ==
                                      SupervisorConnectionStatus.connecting
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.health_and_safety_outlined,
                                    ),
                              label: Text(fa ? 'تست سلامت' : 'Check health'),
                            ),
                          if (snapshot.status !=
                              SupervisorConnectionStatus.notConfigured)
                            TextButton.icon(
                              onPressed:
                                  snapshot.status ==
                                      SupervisorConnectionStatus.connecting
                                  ? null
                                  : () => _confirmRemove(context, fa: fa),
                              icon: const Icon(Icons.link_off_rounded),
                              label: Text(fa ? 'حذف اتصال' : 'Remove'),
                            ),
                        ],
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

  Widget _buildSessionControls(
    BuildContext context,
    SupervisorConnectionStatus connectionStatus, {
    required bool fa,
  }) {
    final status = _sessionController.status;
    final healthy = connectionStatus == SupervisorConnectionStatus.connected;
    final active = status == SupervisorSessionStatus.active;

    if (active) {
      return Semantics(
        container: true,
        label: fa ? 'جلسه فقط خواندنی فعال است' : 'Read-only session is active',
        child: Container(
          key: const ValueKey('supervisor-session-active'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: QuantaraColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: QuantaraColors.success.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fa
                    ? 'جلسه تحلیل فقط‌خواندنی فعال است'
                    : 'Read-only analysis session active',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '${fa ? 'زمان باقی‌مانده' : 'Remaining'}: ${_formatRemaining(_sessionController.remaining)}',
                key: const ValueKey('supervisor-session-remaining'),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('supervisor-session-stop'),
                onPressed: _sessionController.stop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(fa ? 'قطع جلسه' : 'Stop / Disconnect'),
              ),
            ],
          ),
        ),
      );
    }

    final previousEnded =
        status == SupervisorSessionStatus.expired ||
        status == SupervisorSessionStatus.stopped;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('supervisor-session-start'),
          onPressed: healthy
              ? () => _sessionController.start(_sessionDuration)
              : null,
          icon: const Icon(Icons.timer_outlined),
          label: Text(
            previousEnded
                ? (fa
                      ? 'شروع دوباره جلسه ۱۵ دقیقه‌ای'
                      : 'Start another 15 min session')
                : (fa
                      ? 'شروع جلسه ۱۵ دقیقه‌ای'
                      : 'Start 15 min read-only session'),
          ),
        ),
        Text(
          healthy
              ? (fa
                    ? 'شروع جلسه فقط با اقدام صریح شما انجام می‌شود.'
                    : 'The session starts only after your explicit action.')
              : (fa
                    ? 'برای شروع جلسه، ابتدا اتصال سالم Supervisor لازم است.'
                    : 'A healthy Supervisor connection is required before a session can start.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  static String _formatRemaining(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 3600);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _showSetupDialog(
    BuildContext context, {
    required bool fa,
  }) async {
    final urlController = TextEditingController(
      text: widget.controller.snapshot.serverOrigin?.toString() ?? '',
    );
    final tokenController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var saving = false;
          String? validationMessage;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                fa
                    ? 'تنظیم ChatGPT Supervisor'
                    : 'Configure ChatGPT Supervisor',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fa
                          ? 'آدرس HTTPS سرور Quantara Supervisor و توکن کنترل مخصوص این دستگاه را وارد کن.'
                          : 'Enter the HTTPS Quantara Supervisor server and the device-bound control token.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('supervisor-server-url-field'),
                      controller: urlController,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'HTTPS Server URL',
                        hintText: 'https://supervisor.example.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('supervisor-control-token-field'),
                      controller: tokenController,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Control Token',
                        helperText: 'Stored only in device secure storage',
                      ),
                    ),
                    if (validationMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        validationMessage!,
                        key: const ValueKey('supervisor-validation-message'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(fa ? 'لغو' : 'Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                            validationMessage = null;
                          });
                          final validation = await widget.controller
                              .saveAndCheck(
                                serverUrl: urlController.text,
                                controlToken: tokenController.text,
                              );
                          if (!dialogContext.mounted) return;
                          if (!validation.isValid) {
                            setDialogState(() {
                              saving = false;
                              validationMessage = _validationMessage(
                                validation,
                                fa: fa,
                              );
                            });
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                        },
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(fa ? 'ذخیره و تست' : 'Save & test'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      urlController.dispose();
      tokenController.dispose();
    }
  }

  Future<void> _confirmRemove(BuildContext context, {required bool fa}) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(fa ? 'حذف اتصال Supervisor' : 'Remove Supervisor setup'),
        content: Text(
          fa
              ? 'آدرس سرور و توکن کنترل از Secure Storage این دستگاه حذف شوند؟'
              : 'Remove the server address and control token from this device secure storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(fa ? 'لغو' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(fa ? 'حذف' : 'Remove'),
          ),
        ],
      ),
    );
    if (remove == true) {
      _sessionController.stop();
      await widget.controller.clear();
    }
  }

  static String _validationMessage(
    SupervisorSetupValidation validation, {
    required bool fa,
  }) {
    final failures = validation.failures;
    if (failures.contains(SupervisorSetupFailure.insecureServerUrl)) {
      return fa
          ? 'در نسخه Release فقط HTTPS مجاز است.'
          : 'Release builds require HTTPS.';
    }
    if (failures.contains(SupervisorSetupFailure.invalidServerUrl) ||
        failures.contains(SupervisorSetupFailure.missingServerUrl)) {
      return fa ? 'آدرس سرور معتبر نیست.' : 'Enter a valid server URL.';
    }
    if (failures.contains(SupervisorSetupFailure.invalidControlToken) ||
        failures.contains(SupervisorSetupFailure.missingControlToken)) {
      return fa
          ? 'توکن کنترل معتبر و کامل وارد کن.'
          : 'Enter a valid complete control token.';
    }
    return fa ? 'تنظیم اتصال معتبر نیست.' : 'The setup is not valid.';
  }

  static _SupervisorStatusPresentation _presentation(
    SupervisorConnectionStatus status, {
    required bool fa,
  }) {
    return switch (status) {
      SupervisorConnectionStatus.notConfigured => _SupervisorStatusPresentation(
        title: fa ? 'تنظیم نشده' : 'Not configured',
        summary: fa
            ? 'ChatGPT analysis روی این دستگاه تنظیم نشده است.'
            : 'ChatGPT analysis is not configured on this device.',
        color: QuantaraColors.warning,
        icon: Icons.settings_outlined,
      ),
      SupervisorConnectionStatus.connecting => _SupervisorStatusPresentation(
        title: fa ? 'در حال بررسی' : 'Connecting',
        summary: fa
            ? 'سلامت سرور Supervisor در حال بررسی است.'
            : 'Checking the Supervisor server health.',
        color: QuantaraColors.warning,
        icon: Icons.sync_rounded,
      ),
      SupervisorConnectionStatus.connected => _SupervisorStatusPresentation(
        title: fa ? 'متصل' : 'Connected',
        summary: fa
            ? 'اتصال فقط‌خواندنی Supervisor سالم است.'
            : 'The read-only Supervisor connection is healthy.',
        color: QuantaraColors.success,
        icon: Icons.verified_user_outlined,
      ),
      SupervisorConnectionStatus.expired => _SupervisorStatusPresentation(
        title: fa ? 'منقضی' : 'Expired',
        summary: fa
            ? 'توکن کنترل منقضی شده و باید جایگزین شود.'
            : 'The control token expired and must be replaced.',
        color: QuantaraColors.warning,
        icon: Icons.schedule_rounded,
      ),
      SupervisorConnectionStatus.revoked => _SupervisorStatusPresentation(
        title: fa ? 'لغو شده' : 'Revoked',
        summary: fa
            ? 'توکن کنترل لغو شده است؛ اتصال جدید لازم است.'
            : 'The control token was revoked; configure a new connection.',
        color: QuantaraColors.danger,
        icon: Icons.block_rounded,
      ),
      SupervisorConnectionStatus.serverUnreachable =>
        _SupervisorStatusPresentation(
          title: fa ? 'سرور در دسترس نیست' : 'Server unreachable',
          summary: fa
              ? 'اتصال Supervisor برقرار نشد؛ تنظیمات و شبکه را بررسی کن.'
              : 'Supervisor could not be reached; check the setup and network.',
          color: QuantaraColors.warning,
          icon: Icons.cloud_off_outlined,
        ),
      SupervisorConnectionStatus.incompatibleServer =>
        _SupervisorStatusPresentation(
          title: fa ? 'سرور ناسازگار' : 'Incompatible server',
          summary: fa
              ? 'سرور پاسخ می‌دهد اما قرارداد فقط‌خواندنی مورد انتظار Quantara را ندارد.'
              : 'The server responds but does not satisfy Quantara’s read-only contract.',
          color: QuantaraColors.danger,
          icon: Icons.gpp_bad_outlined,
        ),
    };
  }
}

class _SupervisorStatusPresentation {
  const _SupervisorStatusPresentation({
    required this.title,
    required this.summary,
    required this.color,
    required this.icon,
  });

  final String title;
  final String summary;
  final Color color;
  final IconData icon;
}
