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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [QuantaraColors.cyan, QuantaraColors.violet],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const SizedBox.square(
                  dimension: 58,
                  child: Icon(
                    Icons.person_rounded,
                    color: QuantaraColors.ink,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.profileTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(strings.localProfile),
                    Text(
                      strings.noCloudAccount,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.settings,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              Text(
                strings.language,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                strings.languageDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ChoiceChip(
                    label: Text(strings.persian),
                    selected: widget.locale.languageCode == 'fa',
                    onSelected: (_) {
                      widget.onLocaleChanged(const Locale('fa'));
                    },
                  ),
                  ChoiceChip(
                    label: Text(strings.english),
                    selected: widget.locale.languageCode == 'en',
                    onSelected: (_) {
                      widget.onLocaleChanged(const Locale('en'));
                    },
                  ),
                ],
              ),
              const Divider(height: 32),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: widget.themeMode == ThemeMode.dark,
                onChanged: (_) => widget.onToggleTheme(),
                title: Text(
                  widget.themeMode == ThemeMode.dark
                      ? strings.darkAppearance
                      : strings.lightAppearance,
                ),
                subtitle: Text(strings.appearanceDescription),
                secondary: Icon(
                  widget.themeMode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.connections,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              _ProfileConnection(
                icon: Icons.currency_bitcoin_rounded,
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
              const Divider(height: 32),
              _ProfileConnection(
                icon: Icons.vpn_key_off_outlined,
                title: strings.privateAccount,
                subtitle: strings.futureVersion,
                status: StatusPill(
                  label: strings.unavailable,
                  color: QuantaraColors.warning,
                  icon: Icons.lock_outline_rounded,
                ),
                description: strings.privateConnectionDescription,
              ),
              const Divider(height: 32),
              _ProfileConnection(
                icon: Icons.notifications_active_outlined,
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
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: controller.notificationsEnabled,
                title: Text(strings.setupNotifications),
                subtitle: Text(strings.setupNotificationsDescription),
                onChanged: (value) async {
                  final enabled = await controller.setNotificationsEnabled(
                    value,
                  );
                  if (value && !enabled && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(strings.notificationPermissionDenied),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _StrategyCard(),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.riskSettings,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
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
              const SizedBox(height: 8),
              Text(strings.riskSettingsDescription),
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MetricTile(
                    label: strings.baseCapital,
                    value: QuantaraNumberFormat.marketValue(
                      controller.capital,
                      unit: 'USDT',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isLoading
                        ? null
                        : () => _editCapital(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(strings.change),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                strings.riskPerSetup(
                  strings.decimal(controller.riskPercent, decimals: 1),
                ),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              Slider(
                value: _draftRisk ?? controller.riskPercent,
                min: 0.1,
                max: 3,
                divisions: 29,
                label:
                    '${(_draftRisk ?? controller.riskPercent).toStringAsFixed(1)}%',
                onChanged: controller.isLoading
                    ? null
                    : (value) => setState(() => _draftRisk = value),
                onChangeEnd: controller.isLoading
                    ? null
                    : (value) async {
                        await controller.updateRiskSettings(
                          capital: controller.capital,
                          riskPercent: value,
                        );
                        if (mounted) {
                          setState(() => _draftRisk = null);
                        }
                      },
              ),
              Text(
                strings.maximumCalculatedLoss(
                  QuantaraNumberFormat.marketValue(
                    controller.capital * controller.riskPercent / 100,
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
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.securityAndPrivacy,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(strings.securityDescription),
              const Divider(height: 28),
              Text(
                strings.about,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(strings.version, textDirection: TextDirection.ltr),
              Text(
                strings.profileSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileConnection extends StatelessWidget {
  const _ProfileConnection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.description,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget status;
  final String description;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox.square(
                dimension: 48,
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(width: 12),
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
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(alignment: AlignmentDirectional.centerStart, child: status),
        const SizedBox(height: 10),
        Text(description),
        if (detail != null) ...[
          const SizedBox(height: 5),
          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}
