import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../application/windows_service_management_client.dart';
import '../application/windows_service_status_reader.dart';
import '../data/platform_windows_service_management_command.dart';
import '../data/platform_windows_service_status_command.dart';
import '../domain/windows_service_protocol.dart';

class WindowsServiceStatusPill extends StatefulWidget {
  const WindowsServiceStatusPill({
    this.reader,
    this.managementClient,
    this.forceVisible = false,
    super.key,
  });

  final WindowsServiceStatusReader? reader;
  final WindowsServiceManagementClient? managementClient;
  final bool forceVisible;

  @override
  State<WindowsServiceStatusPill> createState() =>
      _WindowsServiceStatusPillState();
}

class _WindowsServiceStatusPillState extends State<WindowsServiceStatusPill> {
  Future<WindowsServiceStatusSnapshot>? _snapshotFuture;

  bool get _visible =>
      widget.forceVisible ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WindowsServiceStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reader != widget.reader ||
        oldWidget.forceVisible != widget.forceVisible) {
      _load();
    }
  }

  void _load() {
    if (!_visible) {
      _snapshotFuture = null;
      return;
    }
    final reader = widget.reader ?? createPlatformWindowsServiceStatusReader();
    _snapshotFuture = reader.read();
  }

  void _retry() {
    setState(_load);
  }

  Future<void> _showCloseExistingPositionDialog() async {
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final controller = TextEditingController();
    final managementClient =
        widget.managementClient ??
        createPlatformWindowsServiceManagementClient();
    var confirmed = false;
    var busy = false;
    String? errorMessage;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final positionId = controller.text.trim();
              final validPositionId =
                  RegExp(r'^[0-9]{1,64}$').hasMatch(positionId) &&
                  positionId != '0';
              final canSubmit = validPositionId && confirmed && !busy;

              Future<void> submit() async {
                if (!canSubmit) {
                  return;
                }
                setDialogState(() {
                  busy = true;
                  errorMessage = null;
                });
                try {
                  final result = await managementClient.closeExistingPosition(
                    positionId,
                  );
                  if (!dialogContext.mounted) {
                    return;
                  }
                  if (!result.completed) {
                    setDialogState(() {
                      busy = false;
                      errorMessage = persian
                          ? 'بسته‌شدن پوزیشن تأیید نشد. پیش از تلاش دوباره، وضعیت صرافی را دوباره تطبیق دهید.'
                          : 'Position close was not confirmed. Reconcile exchange state before retrying.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  if (!mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        persian
                            ? 'بسته‌شدن پوزیشن با وضعیت تازه صرافی تأیید شد.'
                            : 'Position close was confirmed by fresh exchange state.',
                      ),
                    ),
                  );
                  _retry();
                } on WindowsServiceManagementException {
                  if (!dialogContext.mounted) {
                    return;
                  }
                  setDialogState(() {
                    busy = false;
                    errorMessage = persian
                        ? 'نتیجه عملیات قابل تأیید نیست. پیش از تلاش دوباره، وضعیت صرافی را تطبیق دهید.'
                        : 'The operation outcome is not verified. Reconcile exchange state before retrying.';
                  });
                }
              }

              return AlertDialog(
                title: Text(
                  persian ? 'بستن پوزیشن موجود' : 'Close existing position',
                ),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persian
                            ? 'فقط پوزیشن موجودی که Quantara آن را دوباره با صرافی تأیید کند قابل بستن است. این مسیر هیچ اختیار ورود جدیدی ایجاد نمی‌کند.'
                            : 'Only an existing position re-verified by Quantara against the exchange can be closed. This path never grants new-entry authority.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: persian ? 'Position ID' : 'Position ID',
                          helperText: persian
                              ? 'شناسه عددی پوزیشن در صرافی'
                              : 'Numeric exchange position identifier',
                          errorText: controller.text.isEmpty || validPositionId
                              ? null
                              : (persian
                                    ? 'شناسه باید ۱ تا ۶۴ رقم و غیرصفر باشد.'
                                    : 'ID must be 1-64 decimal digits and non-zero.'),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: confirmed,
                        onChanged: busy
                            ? null
                            : (value) {
                                setDialogState(() {
                                  confirmed = value ?? false;
                                });
                              },
                        title: Text(
                          persian
                              ? 'تأیید می‌کنم فقط همین پوزیشن موجود بسته شود.'
                              : 'I confirm that only this existing position should be closed.',
                        ),
                        subtitle: Text(
                          persian
                              ? 'در صورت نامشخص بودن نتیجه شبکه، عملیات خودکار تکرار نمی‌شود.'
                              : 'If the network outcome is ambiguous, the mutation is not retried automatically.',
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: TextStyle(color: QuantaraColors.danger),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: Text(persian ? 'انصراف' : 'Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: canSubmit ? submit : null,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close_rounded),
                    label: Text(
                      busy
                          ? (persian ? 'در حال تأیید…' : 'Confirming…')
                          : (persian ? 'بستن پوزیشن' : 'Close position'),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    return FutureBuilder<WindowsServiceStatusSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return StatusPill(
            label: persian ? 'بررسی سرویس ویندوز' : 'Checking Windows service',
            color: QuantaraColors.cyan,
            icon: Icons.sync_rounded,
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Tooltip(
            message: persian
                ? 'وضعیت سرویس قابل تأیید نیست؛ اختیار ورود جدید غیرفعال می‌ماند.'
                : 'Service status cannot be verified; new-entry authority remains disabled.',
            child: InkWell(
              onTap: _retry,
              borderRadius: BorderRadius.circular(999),
              child: StatusPill(
                label: persian
                    ? 'سرویس ویندوز: نامطمئن'
                    : 'Windows service: unverified',
                color: QuantaraColors.warning,
                icon: Icons.shield_outlined,
              ),
            ),
          );
        }
        final status = snapshot.requireData;
        final presentation = _presentation(status.safetyState, persian);
        final managementEnabled =
            status.safetyState == WindowsServiceSafetyState.manageExistingOnly;
        final pill = StatusPill(
          label: presentation.label,
          color: presentation.color,
          icon: presentation.icon,
        );
        return Tooltip(
          message: managementEnabled
              ? (persian
                    ? '${presentation.detail} برای بستن یک پوزیشن موجود کلیک کنید. اختیار ورود جدید: غیرفعال.'
                    : '${presentation.detail} Click to close a verified existing position. New-entry authority: disabled.')
              : (persian
                    ? '${presentation.detail} اختیار ورود جدید: غیرفعال.'
                    : '${presentation.detail} New-entry authority: disabled.'),
          child: managementEnabled
              ? InkWell(
                  onTap: _showCloseExistingPositionDialog,
                  borderRadius: BorderRadius.circular(999),
                  child: pill,
                )
              : pill,
        );
      },
    );
  }
}

_ServiceStatusPresentation _presentation(
  WindowsServiceSafetyState state,
  bool persian,
) {
  return switch (state) {
    WindowsServiceSafetyState.disarmed => _ServiceStatusPresentation(
      label: persian ? 'سرویس ویندوز: غیرفعال' : 'Windows service: disarmed',
      detail: persian
          ? 'سرویس احراز شده و در حالت بدون اختیار معامله است.'
          : 'The authenticated service is running without trading authority.',
      color: QuantaraColors.cyan,
      icon: Icons.shield_outlined,
    ),
    WindowsServiceSafetyState.interrupted => _ServiceStatusPresentation(
      label: persian ? 'سرویس ویندوز: وقفه' : 'Windows service: interrupted',
      detail: persian
          ? 'چرخه سرویس قطع شده و بازیابی خودکار مجاز نیست.'
          : 'The service lifecycle was interrupted and cannot auto-resume.',
      color: QuantaraColors.danger,
      icon: Icons.error_outline_rounded,
    ),
    WindowsServiceSafetyState.reconciliationRequired =>
      _ServiceStatusPresentation(
        label: persian
            ? 'سرویس ویندوز: نیازمند تطبیق'
            : 'Windows service: reconcile',
        detail: persian
            ? 'پیش از هر اختیار آینده، تطبیق تازه لازم است.'
            : 'Fresh reconciliation is required before any future authority.',
        color: QuantaraColors.warning,
        icon: Icons.sync_problem_rounded,
      ),
    WindowsServiceSafetyState.manageExistingOnly => _ServiceStatusPresentation(
      label: persian
          ? 'سرویس ویندوز: فقط مدیریت پوزیشن'
          : 'Windows service: manage existing only',
      detail: persian
          ? 'فقط مدیریت پوزیشن‌های موجود و تأییدشده مجاز است.'
          : 'Only verified existing positions may be managed.',
      color: QuantaraColors.warning,
      icon: Icons.admin_panel_settings_outlined,
    ),
  };
}

final class _ServiceStatusPresentation {
  const _ServiceStatusPresentation({
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
  });

  final String label;
  final String detail;
  final Color color;
  final IconData icon;
}
