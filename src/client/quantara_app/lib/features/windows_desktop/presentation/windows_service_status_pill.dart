import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../application/windows_service_status_reader.dart';
import '../data/platform_windows_service_status_command.dart';
import '../domain/windows_service_protocol.dart';

class WindowsServiceStatusPill extends StatefulWidget {
  const WindowsServiceStatusPill({
    this.reader,
    this.forceVisible = false,
    super.key,
  });

  final WindowsServiceStatusReader? reader;
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
    final reader =
        widget.reader ?? createPlatformWindowsServiceStatusReader();
    _snapshotFuture = reader.read();
  }

  void _retry() {
    setState(_load);
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
        return Tooltip(
          message: persian
              ? '${presentation.detail} اختیار ورود جدید: غیرفعال.'
              : '${presentation.detail} New-entry authority: disabled.',
          child: StatusPill(
            label: presentation.label,
            color: presentation.color,
            icon: presentation.icon,
          ),
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
