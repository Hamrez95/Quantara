import 'package:flutter/material.dart';

import '../application/global_pause_runtime_policy.dart';

/// Presentation-only control for the canonical Global Pause runtime state.
///
/// This widget never arms the robot or grants entry authority. It delegates
/// Pause/Resume requests to the runtime owner, which must perform the
/// fail-closed reconciliation/protection checks before changing state.
final class GlobalPauseControl extends StatelessWidget {
  const GlobalPauseControl({
    super.key,
    required this.mode,
    required this.persian,
    required this.onPauseRequested,
    required this.onResumeRequested,
    this.pauseFullyWhenFlat = false,
    this.onPauseFullyWhenFlatChanged,
  });

  final GlobalPauseRuntimeMode mode;
  final bool persian;
  final VoidCallback? onPauseRequested;
  final VoidCallback? onResumeRequested;
  final bool pauseFullyWhenFlat;
  final ValueChanged<bool>? onPauseFullyWhenFlatChanged;

  bool get _isRunning => mode == GlobalPauseRuntimeMode.running;
  bool get _isResuming => mode == GlobalPauseRuntimeMode.resuming;
  bool get _isSafePause =>
      mode == GlobalPauseRuntimeMode.safePausedManagingExisting;
  bool get _isOffline => mode == GlobalPauseRuntimeMode.pausedOffline;

  String _t(String fa, String en) => persian ? fa : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paused = _isSafePause || _isOffline;

    return Semantics(
      container: true,
      label: _t('کنترل توقف سراسری ربات', 'Robot global pause control'),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _isRunning ? Icons.play_circle_outline : Icons.pause_circle,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('global-pause-primary-action'),
                    onPressed: _isResuming
                        ? null
                        : _isRunning
                        ? onPauseRequested
                        : onResumeRequested,
                    icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                    label: Text(
                      _isRunning
                          ? _t('توقف سراسری', 'Global Pause')
                          : _isResuming
                          ? _t('در حال بررسی…', 'Validating…')
                          : _t('ادامه', 'Resume'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_statusBody, style: theme.textTheme.bodySmall),
              if (_isSafePause) ...[
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  key: const ValueKey('pause-fully-when-flat'),
                  contentPadding: EdgeInsets.zero,
                  value: pauseFullyWhenFlat,
                  onChanged: onPauseFullyWhenFlatChanged,
                  title: Text(
                    _t('توقف کامل پس از بسته‌شدن پوزیشن‌ها', 'Pause fully when flat'),
                  ),
                  subtitle: Text(
                    _t(
                      'تا وقتی مدیریت پوزیشن باز لازم است، فقط پایش ایمنی حداقلی فعال می‌ماند.',
                      'Only minimum safety monitoring remains active while open exposure still needs management.',
                    ),
                  ),
                ),
              ],
              if (paused) ...[
                const SizedBox(height: 8),
                Text(
                  _t(
                    'ادامه‌دادن هیچ‌وقت خودکار نیست؛ ابتدا تازگی حساب، reconciliation و حفاظت بررسی می‌شود.',
                    'Resume is never automatic; account freshness, reconciliation, and protection are validated first.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _statusTitle => switch (mode) {
    GlobalPauseRuntimeMode.running => _t('ربات فعال است', 'Robot is running'),
    GlobalPauseRuntimeMode.safePausedManagingExisting =>
      _t('توقف امن — مدیریت پوزیشن‌های موجود', 'Safe Pause — managing existing exposure'),
    GlobalPauseRuntimeMode.pausedOffline =>
      _t('توقف کامل — آفلاین', 'Fully paused — offline'),
    GlobalPauseRuntimeMode.resuming =>
      _t('در حال اعتبارسنجی ادامه کار', 'Validating resume'),
  };

  String get _statusBody => switch (mode) {
    GlobalPauseRuntimeMode.running => _t(
      'اسکن و ورود فقط تحت گیت‌های فعلی ریسک و تازگی حساب ادامه دارد.',
      'Scanning and entries continue only through the existing risk and account-freshness gates.',
    ),
    GlobalPauseRuntimeMode.safePausedManagingExisting => _t(
      'ورود و اسکن جدید متوقف است؛ پایش خصوصی حداقلی برای رها نکردن پوزیشن/سفارش موجود حفظ می‌شود.',
      'New scanning and entries are stopped; minimum private monitoring remains so existing exposure is never abandoned.',
    ),
    GlobalPauseRuntimeMode.pausedOffline => _t(
      'اسکن، ورود و کار پس‌زمینه غیرضروری متوقف است.',
      'Scanning, entries, and non-essential background work are stopped.',
    ),
    GlobalPauseRuntimeMode.resuming => _t(
      'تا تکمیل بررسی حساب و حفاظت، ورود مجاز نمی‌شود.',
      'Entries remain disabled until account and protection validation completes.',
    ),
  };
}
