part of 'owner_alpha_page.dart';

class _ProfileView extends StatefulWidget {
  const _ProfileView({
    required this.controller,
    required this.themeMode,
    required this.locale,
    required this.onToggleTheme,
    required this.onLocaleChanged,
  });

  final OwnerAlphaController controller;
  final ThemeMode themeMode;
  final Locale locale;
  final VoidCallback onToggleTheme;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  double? _draftRisk;

  OwnerAlphaController get controller => widget.controller;

  Future<void> _editCapital(BuildContext context) async {
    final strings = AppStrings.of(context);
    final textController = TextEditingController(
      text: controller.capital.toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.capitalDialogTitle),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'Capital (USDT)',
            helperText: strings.capitalHelper,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(textController.text.trim());
              if (parsed != null && parsed >= 100) {
                Navigator.pop(context, parsed);
              }
            },
            child: Text(strings.save),
          ),
        ],
      ),
    );
    textController.dispose();
    if (value != null) {
      await controller.updateRiskSettings(
        capital: value,
        riskPercent: controller.riskPercent,
      );
    }
  }

  Future<void> _copySettingsBackup(BuildContext context) async {
    final persian = widget.locale.languageCode == 'fa';
    final payload = OwnerAlphaSettingsTransfer.encode(
      OwnerAlphaSettings(
        symbols: controller.symbols,
        capital: controller.capital,
        riskPercent: controller.riskPercent,
        strategy: controller.strategy,
        cadence: controller.cadence,
      ),
    );
    await Clipboard.setData(ClipboardData(text: payload));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persian
              ? 'نسخه پشتیبان تنظیمات در کلیپ‌بورد کپی شد. این متن شامل کلید API نیست.'
              : 'Settings backup copied to the clipboard. It contains no API credentials.',
        ),
      ),
    );
  }

  Future<void> _restoreSettingsBackup(BuildContext context) async {
    final persian = widget.locale.languageCode == 'fa';
    try {
      final clipboard = await Clipboard.getData('text/plain');
      final text = clipboard?.text;
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('empty clipboard');
      }
      final settings = OwnerAlphaSettingsTransfer.decode(text);
      final error = await controller.restoreSettings(settings);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ??
                (persian
                    ? 'واچ‌لیست و تنظیمات مدیریت سرمایه بازیابی شد.'
                    : 'Watchlist and risk settings were restored.'),
          ),
        ),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            persian
                ? 'متن معتبر پشتیبان Quantara در کلیپ‌بورد پیدا نشد.'
                : 'No valid Quantara settings backup was found in the clipboard.',
          ),
        ),
      );
    }
  }

  Future<void> _setNotifications(BuildContext context, bool value) async {
    final strings = AppStrings.of(context);
    final enabled = await controller.setNotificationsEnabled(value);
    if (!context.mounted) return;
    if (value && !enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.notificationPermissionDenied)),
      );
      return;
    }
    if (value && enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.locale.languageCode == 'fa'
                ? 'پایش فعال شد؛ یک اسکن اولیه و سپس بررسی‌های دوره‌ای انجام می‌شود.'
                : 'Monitoring is on. An initial scan and periodic checks are scheduled.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileHero(
          controller: controller,
          locale: widget.locale,
          title: strings.profileTitle,
          subtitle: strings.localProfile,
          caption: strings.noCloudAccount,
        ),
        const SizedBox(height: 16),
        _ProfileSummary(controller: controller),
        const SizedBox(height: 16),
        _ProfilePreferencesCard(
          themeMode: widget.themeMode,
          locale: widget.locale,
          onToggleTheme: widget.onToggleTheme,
          onLocaleChanged: widget.onLocaleChanged,
        ),
        const SizedBox(height: 16),
        _ProfileConnectionsCard(
          controller: controller,
          locale: widget.locale,
          onNotificationsChanged: (value) =>
              _setNotifications(context, value),
        ),
        const SizedBox(height: 16),
        const _StrategyCard(),
        const SizedBox(height: 16),
        _ProfileRiskCard(
          controller: controller,
          draftRisk: _draftRisk,
          onDraftChanged: (value) => setState(() => _draftRisk = value),
          onRiskCommitted: (value) async {
            await controller.updateRiskSettings(
              capital: controller.capital,
              riskPercent: value,
            );
            if (mounted) {
              setState(() => _draftRisk = null);
            }
          },
          onEditCapital: () => _editCapital(context),
        ),
        const SizedBox(height: 16),
        _ProfileBackupCard(
          locale: widget.locale,
          onCopy: () => _copySettingsBackup(context),
          onRestore: () => _restoreSettingsBackup(context),
        ),
        const SizedBox(height: 16),
        _ProfileAboutCard(locale: widget.locale),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.controller,
    required this.locale,
    required this.title,
    required this.subtitle,
    required this.caption,
  });

  final OwnerAlphaController controller;
  final Locale locale;
  final String title;
  final String subtitle;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fresh =
        controller.connectionState == OwnerAlphaConnectionState.fresh ||
        controller.connectionState == OwnerAlphaConnectionState.refreshing;
    return Semantics(
      container: true,
      label: '$title. $subtitle. $caption',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(QuantaraRadius.large),
          border: Border.all(
            color: QuantaraColors.violet.withValues(alpha: 0.32),
          ),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              Color.alphaBlend(
                QuantaraColors.electricBlue.withValues(alpha: 0.18),
                scheme.surface,
              ),
              Color.alphaBlend(
                QuantaraColors.violet.withValues(alpha: 0.14),
                scheme.surface,
              ),
              scheme.surface,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: QuantaraColors.violet.withValues(alpha: 0.11),
              blurRadius: 30,
              spreadRadius: -16,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -60,
              end: -48,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      QuantaraColors.cyan.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 70,
                            height: 70,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: QuantaraColors.brandGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: QuantaraColors.cyan.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: -8,
                                ),
                              ],
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.surface,
                              ),
                              child: const Center(
                                child: QuantaraBrandMark(size: 48),
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            end: -2,
                            bottom: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: fresh
                                    ? QuantaraColors.success
                                    : QuantaraColors.warning,
                                border: Border.all(
                                  color: scheme.surface,
                                  width: 3,
                                ),
                              ),
                              child: const SizedBox.square(dimension: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(color: QuantaraColors.cyan),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              caption,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final badge = StatusPill(
                    label: locale.languageCode == 'fa'
                        ? 'پروفایل محلی امن'
                        : 'Secure local profile',
                    color: QuantaraColors.success,
                    icon: Icons.verified_user_outlined,
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        const SizedBox(height: 14),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: badge,
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 16),
                      badge,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.controller});

  final OwnerAlphaController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final items = <_ProfileMetricData>[
      _ProfileMetricData(
        icon: Icons.account_balance_wallet_outlined,
        label: strings.baseCapital,
        value: QuantaraNumberFormat.marketValue(
          controller.capital,
          unit: 'USDT',
        ),
        color: QuantaraColors.cyan,
      ),
      _ProfileMetricData(
        icon: Icons.shield_outlined,
        label: strings.t('ریسک هر پیشنهاد', 'Risk per setup'),
        value: '${controller.riskPercent.toStringAsFixed(1)}%',
        color: QuantaraColors.success,
      ),
      _ProfileMetricData(
        icon: Icons.visibility_outlined,
        label: strings.t('نمادهای واچ‌لیست', 'Watchlist symbols'),
        value: '${controller.symbols.length}',
        color: QuantaraColors.violet,
      ),
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: strings.t('نمای کلی حساب', 'Account overview'),
            subtitle: strings.t(
              'خلاصه واقعی تنظیمات فعال Quantara',
              'A real summary of active Quantara settings',
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 3 : 1;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: width,
                      child: _ProfileSummaryMetric(data: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileSummaryMetric extends StatelessWidget {
  const _ProfileSummaryMetric({required this.data});

  final _ProfileMetricData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.square(
                dimension: 38,
                child: Icon(data.icon, size: 20, color: data.color),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.value,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: data.color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePreferencesCard extends StatelessWidget {
  const _ProfilePreferencesCard({
    required this.themeMode,
    required this.locale,
    required this.onToggleTheme,
    required this.onLocaleChanged,
  });

  final ThemeMode themeMode;
  final Locale locale;
  final VoidCallback onToggleTheme;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      accentColor: QuantaraColors.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSectionHeader(
            icon: Icons.tune_rounded,
            color: QuantaraColors.violet,
            title: strings.settings,
            subtitle: strings.t(
              'زبان، ظاهر و تجربه کاربری',
              'Language, appearance and experience',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            strings.language,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            strings.languageDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment<String>(
                value: 'fa',
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(strings.persian),
              ),
              ButtonSegment<String>(
                value: 'en',
                icon: const Icon(Icons.language_rounded),
                label: Text(strings.english),
              ),
            ],
            selected: {locale.languageCode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              onLocaleChanged(Locale(selection.first));
            },
          ),
          const Divider(height: 32),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: themeMode == ThemeMode.dark,
            onChanged: (_) => onToggleTheme(),
            title: Text(
              themeMode == ThemeMode.dark
                  ? strings.darkAppearance
                  : strings.lightAppearance,
            ),
            subtitle: Text(strings.appearanceDescription),
            secondary: DecoratedBox(
              decoration: BoxDecoration(
                color: QuantaraColors.violet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.square(
                dimension: 42,
                child: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  color: QuantaraColors.violet,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileConnectionsCard extends StatelessWidget {
  const _ProfileConnectionsCard({
    required this.controller,
    required this.locale,
    required this.onNotificationsChanged,
  });

  final OwnerAlphaController controller;
  final Locale locale;
  final ValueChanged<bool> onNotificationsChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final lastBackground = controller.lastBackgroundScanAt == null
        ? (locale.languageCode == 'fa'
              ? 'هنوز اسکن پس‌زمینه ثبت نشده است.'
              : 'No background scan has been recorded yet.')
        : (locale.languageCode == 'fa'
              ? 'آخرین اسکن پس‌زمینه: ${controller.lastBackgroundScanAt!.toLocal()}'
              : 'Last background scan: ${controller.lastBackgroundScanAt!.toLocal()}');
    return SectionCard(
      accentColor: QuantaraColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSectionHeader(
            icon: Icons.link_rounded,
            color: QuantaraColors.cyan,
            title: strings.connections,
            subtitle: strings.t(
              'وضعیت بازار، حساب خصوصی و پایش',
              'Market, private account and monitoring status',
            ),
          ),
          const SizedBox(height: 16),
          _ProfileConnectionCard(
            icon: Icons.currency_bitcoin_rounded,
            color: QuantaraColors.cyan,
            title: strings.bitunixFutures,
            subtitle: strings.publicMarketConnection,
            status: _ConnectionStatusPill(controller: controller),
            description: strings.publicConnectionDescription,
            detail: controller.snapshot == null
                ? null
                : strings.lastScan(
                    DateTime.now().toUtc().difference(
                      controller.snapshot!.generatedAt,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          _ProfileConnectionCard(
            icon: Icons.key_outlined,
            color: QuantaraColors.warning,
            title: strings.privateAccount,
            subtitle: strings.futureVersion,
            status: StatusPill(
              label: strings.unavailable,
              color: QuantaraColors.warning,
              icon: Icons.lock_outline_rounded,
            ),
            description: strings.privateConnectionDescription,
          ),
          const SizedBox(height: 12),
          _ProfileConnectionCard(
            icon: Icons.sensors_rounded,
            color: controller.notificationsEnabled
                ? QuantaraColors.success
                : QuantaraColors.warning,
            title: strings.backgroundMonitoring,
            subtitle: strings.setupNotifications,
            status: StatusPill(
              label: controller.notificationsEnabled
                  ? strings.active
                  : strings.unavailable,
              color: controller.notificationsEnabled
                  ? QuantaraColors.success
                  : QuantaraColors.warning,
            ),
            description: strings.setupNotificationsDescription,
            detail: lastBackground,
          ),
          const Divider(height: 28),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: controller.notificationsEnabled,
            title: Text(strings.setupNotifications),
            subtitle: Text(strings.setupNotificationsDescription),
            secondary: const Icon(Icons.notifications_active_outlined),
            onChanged: onNotificationsChanged,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: controller.openBackgroundSettings,
              icon: const Icon(Icons.battery_saver_outlined),
              label: Text(
                locale.languageCode == 'fa'
                    ? 'تنظیمات باتری و پس‌زمینه'
                    : 'Battery & background settings',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            locale.languageCode == 'fa'
                ? 'برای اعلان قابل‌اعتمادتر، Quantara را روی حالت Restricted نگذار. Force Stop تا اجرای دوباره اپ، پایش را متوقف می‌کند.'
                : 'For more reliable alerts, do not set Quantara to Restricted. Force Stop pauses monitoring until the app is opened again.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (controller.lastBackgroundError != null) ...[
            const SizedBox(height: 8),
            Text(
              locale.languageCode == 'fa'
                  ? 'آخرین اسکن پس‌زمینه کامل نشد؛ در اتصال بعدی دوباره تلاش می‌کنیم.'
                  : 'The last background scan did not complete; it will retry when possible.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: QuantaraColors.warning,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileConnectionCard extends StatelessWidget {
  const _ProfileConnectionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.description,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget status;
  final String description;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 42,
                    child: Icon(icon, size: 22, color: color),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: status),
              ],
            ),
            const SizedBox(height: 10),
            Text(description),
            if (detail != null) ...[
              const SizedBox(height: 5),
              Text(
                detail!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileRiskCard extends StatelessWidget {
  const _ProfileRiskCard({
    required this.controller,
    required this.draftRisk,
    required this.onDraftChanged,
    required this.onRiskCommitted,
    required this.onEditCapital,
  });

  final OwnerAlphaController controller;
  final double? draftRisk;
  final ValueChanged<double> onDraftChanged;
  final ValueChanged<double> onRiskCommitted;
  final VoidCallback onEditCapital;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final risk = draftRisk ?? controller.riskPercent;
    final maximumLoss = controller.capital * risk / 100;
    return SectionCard(
      accentColor: QuantaraColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ProfileSectionHeader(
                  icon: Icons.health_and_safety_outlined,
                  color: QuantaraColors.success,
                  title: strings.riskSettings,
                  subtitle: strings.riskSettingsDescription,
                ),
              ),
              _InfoButton(
                title: strings.riskSettings,
                paragraphs: [
                  strings.riskSettingsDescription,
                  strings.leverageCaption,
                  strings.lossEstimateWarning,
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final capital = FinanceMetricPanel(
                label: strings.baseCapital,
                value: QuantaraNumberFormat.marketValue(
                  controller.capital,
                  unit: 'USDT',
                ),
                icon: Icons.account_balance_wallet_outlined,
                color: QuantaraColors.cyan,
              );
              final loss = FinanceMetricPanel(
                label: strings.t('حد زیان محاسباتی', 'Calculated loss cap'),
                value: QuantaraNumberFormat.marketValue(
                  maximumLoss,
                  unit: 'USDT',
                ),
                icon: Icons.shield_outlined,
                color: QuantaraColors.success,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    capital,
                    const SizedBox(height: 10),
                    loss,
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: controller.isLoading ? null : onEditCapital,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(strings.change),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: capital),
                  const SizedBox(width: 10),
                  Expanded(child: loss),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: controller.isLoading ? null : onEditCapital,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(strings.change),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.riskPerSetup(
                    strings.decimal(risk, decimals: 1),
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${risk.toStringAsFixed(1)}%',
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: QuantaraColors.success,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Slider(
            value: risk,
            min: 0.1,
            max: 2,
            divisions: 19,
            label: '${risk.toStringAsFixed(1)}%',
            onChanged: controller.isLoading ? null : onDraftChanged,
            onChangeEnd: controller.isLoading ? null : onRiskCommitted,
          ),
          Text(
            strings.maximumCalculatedLoss(
              QuantaraNumberFormat.marketValue(
                maximumLoss,
                unit: 'USDT',
              ),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            strings.lossEstimateWarning,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProfileBackupCard extends StatelessWidget {
  const _ProfileBackupCard({
    required this.locale,
    required this.onCopy,
    required this.onRestore,
  });

  final Locale locale;
  final VoidCallback onCopy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final persian = locale.languageCode == 'fa';
    return SectionCard(
      accentColor: QuantaraColors.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSectionHeader(
            icon: Icons.cloud_sync_outlined,
            color: QuantaraColors.violet,
            title: persian ? 'پشتیبان تنظیمات' : 'Settings backup',
            subtitle: persian
                ? 'انتقال امن تنظیمات بدون کلید API'
                : 'Secure settings transfer without API keys',
          ),
          const SizedBox(height: 10),
          Text(
            persian
                ? 'واچ‌لیست، سرمایه فرضی، ریسک و سیاست سیگنال را بدون اطلاعات محرمانه کپی یا بازیابی کن.'
                : 'Copy or restore watchlist, assumed capital, risk and signal policy without sensitive credentials.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_all_rounded),
                label: Text(persian ? 'کپی پشتیبان' : 'Copy backup'),
              ),
              FilledButton.tonalIcon(
                onPressed: onRestore,
                icon: const Icon(Icons.content_paste_go_rounded),
                label: Text(
                  persian ? 'بازیابی از کلیپ‌بورد' : 'Restore from clipboard',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileAboutCard extends StatelessWidget {
  const _ProfileAboutCard({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileSectionHeader(
            icon: Icons.security_rounded,
            color: QuantaraColors.cyan,
            title: strings.securityAndPrivacy,
            subtitle: locale.languageCode == 'fa'
                ? 'امنیت، حریم خصوصی و شفافیت'
                : 'Security, privacy and transparency',
          ),
          const SizedBox(height: 10),
          Text(strings.securityDescription),
          const Divider(height: 28),
          Text(
            strings.about,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(strings.version, textDirection: TextDirection.ltr),
          Text(
            strings.profileSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: SizedBox.square(
            dimension: 44,
            child: Icon(icon, size: 22, color: color),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ProfileMetricData {
  const _ProfileMetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}
