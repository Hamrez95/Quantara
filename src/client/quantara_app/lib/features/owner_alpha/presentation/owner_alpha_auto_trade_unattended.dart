part of 'owner_alpha_page.dart';

class _UnattendedAutoTradeControlCard extends StatefulWidget {
  const _UnattendedAutoTradeControlCard({
    required this.controller,
    required this.accountController,
    required this.analysisController,
  });

  final UnattendedAutoTradeController controller;
  final AutoTradeController accountController;
  final OwnerAlphaController analysisController;

  @override
  State<_UnattendedAutoTradeControlCard> createState() =>
      _UnattendedAutoTradeControlCardState();
}

class _UnattendedAutoTradeControlCardState
    extends State<_UnattendedAutoTradeControlCard> {
  final Set<String> _enabledSymbols = {};
  final Set<String> _enabledTimeframes = {'1h', '4h'};
  int _leverage = 10;
  double _dailyLossLimit = 2;
  int _maximumPositions = 2;

  bool get _fa => Directionality.of(context) == TextDirection.rtl;

  String _t(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _enabledSymbols.addAll(widget.analysisController.symbols);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.accountController,
        widget.analysisController,
      ]),
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        final armed = snapshot?.state == UnattendedRunState.armed;
        final managing =
            snapshot?.state == UnattendedRunState.managingExistingPositions;
        final breaker = snapshot?.state == UnattendedRunState.circuitBreaker;
        final color = armed
            ? QuantaraColors.success
            : breaker
            ? QuantaraColors.danger
            : managing
            ? QuantaraColors.warning
            : QuantaraColors.cyan;
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      armed
                          ? Icons.power_settings_new_rounded
                          : breaker
                          ? Icons.gpp_bad_outlined
                          : Icons.bedtime_outlined,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('اجرای شبانه و بدون نیاز به گوشی', 'Unattended overnight execution'),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _t(
                            'سرور همیشه‌روشن مسئول ورود، حفاظت، خروج و گزارش صبح است.',
                            'The always-on server owns entries, protection, exits, and the morning report.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: _stateLabel(snapshot?.state),
                    color: color,
                    icon: armed
                        ? Icons.play_arrow_rounded
                        : breaker
                        ? Icons.warning_amber_rounded
                        : Icons.stop_circle_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _BoundaryNotice(
                text: _t(
                  'خاموش‌شدن اپ یا خواب گوشی نباید اجرای معامله را متوقف کند. شروع واقعی فقط وقتی فعال می‌شود که سرور، WebSocket خصوصی و محافظت SL همگی سالم باشند.',
                  'Closing the app or sleeping the phone must not stop execution. Real Start is enabled only when the server, private WebSocket, and protective-stop cycle are healthy.',
                ),
                color: QuantaraColors.warning,
              ),
              if (widget.controller.error != null) ...[
                const SizedBox(height: 12),
                _BoundaryNotice(
                  text: widget.controller.error!,
                  color: QuantaraColors.danger,
                ),
              ],
              const SizedBox(height: 14),
              if (!widget.controller.isConfigured)
                FilledButton.icon(
                  onPressed: widget.controller.isBusy
                      ? null
                      : _showServerConfiguration,
                  icon: const Icon(Icons.dns_outlined),
                  label: Text(
                    _t('اتصال به سرور همیشه‌روشن', 'Connect always-on server'),
                  ),
                )
              else ...[
                _serverSummary(),
                const SizedBox(height: 14),
                _executionSettings(enabled: !armed && !managing),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: QuantaraColors.success,
                          foregroundColor: QuantaraColors.ink,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed:
                            widget.controller.isBusy || armed || managing || breaker
                            ? null
                            : _confirmStart,
                        icon: widget.controller.isBusy
                            ? const SizedBox.square(
                                dimension: 19,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          _t('شروع ترید خودکار', 'Start Auto Trade'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: QuantaraColors.danger,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed:
                            widget.controller.isBusy || (!armed && !managing)
                            ? null
                            : _confirmStop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(
                          _t('قطع ترید', 'Stop Auto Trade'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: widget.controller.isBusy
                          ? null
                          : widget.controller.refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_t('به‌روزرسانی وضعیت', 'Refresh status')),
                    ),
                    TextButton.icon(
                      onPressed: widget.controller.isBusy || armed || managing
                          ? null
                          : widget.controller.disconnectServer,
                      icon: const Icon(Icons.link_off_rounded),
                      label: Text(_t('حذف اتصال سرور', 'Remove server connection')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _serverSummary() {
    final config = widget.controller.serverConfig!;
    final snapshot = widget.controller.snapshot;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuantaraColors.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: QuantaraColors.cyan.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.baseUrl.host,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            '${_t('توکن کنترل', 'Control token')}: ${config.maskedToken}',
            textDirection: TextDirection.ltr,
          ),
          if (snapshot != null)
            Text(
              '${_t('آخرین وضعیت', 'Last status')}: ${_stateLabel(snapshot.state)} · v${snapshot.version}',
            ),
          if (snapshot?.lastReason.isNotEmpty == true)
            Text(snapshot!.lastReason, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _executionSettings({required bool enabled}) {
    final symbols = widget.analysisController.symbols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('نمادهای مجاز برای اجرای خودکار', 'Allowed auto-trade symbols'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final symbol in symbols)
              FilterChip(
                label: Text(symbol, textDirection: TextDirection.ltr),
                selected: _enabledSymbols.contains(symbol),
                onSelected: enabled
                    ? (selected) => setState(() {
                        selected
                            ? _enabledSymbols.add(symbol)
                            : _enabledSymbols.remove(symbol);
                      })
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _t('تایم‌فریم‌های اجرای مجاز', 'Allowed execution timeframes'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final timeframe in const ['15m', '1h', '4h'])
              FilterChip(
                label: Text(timeframe, textDirection: TextDirection.ltr),
                selected: _enabledTimeframes.contains(timeframe),
                onSelected: enabled
                    ? (selected) => setState(() {
                        selected
                            ? _enabledTimeframes.add(timeframe)
                            : _enabledTimeframes.remove(timeframe);
                      })
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 14),
        _numberRow(
          label: _t('اهرم عمومی', 'Global leverage'),
          value: '${_leverage}x',
          enabled: enabled,
          onMinus: () => setState(() => _leverage = math.max(1, _leverage - 1)),
          onPlus: () => setState(() => _leverage = math.min(125, _leverage + 1)),
        ),
        _numberRow(
          label: _t('سقف ضرر روزانه', 'Daily loss limit'),
          value: '${_dailyLossLimit.toStringAsFixed(1)}%',
          enabled: enabled,
          onMinus: () => setState(
            () => _dailyLossLimit = math.max(0.5, _dailyLossLimit - 0.5),
          ),
          onPlus: () => setState(
            () => _dailyLossLimit = math.min(10, _dailyLossLimit + 0.5),
          ),
        ),
        _numberRow(
          label: _t('حداکثر پوزیشن هم‌زمان', 'Maximum concurrent positions'),
          value: '$_maximumPositions',
          enabled: enabled,
          onMinus: () => setState(
            () => _maximumPositions = math.max(1, _maximumPositions - 1),
          ),
          onPlus: () => setState(
            () => _maximumPositions = math.min(20, _maximumPositions + 1),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _t(
            'ریسک هر معامله از تنظیم فعلی اپ (${widget.analysisController.riskPercent.toStringAsFixed(1)}٪) و سرمایه واقعی حساب Bitunix محاسبه می‌شود؛ اهرم فقط مارجین لازم را تغییر می‌دهد.',
            'Per-trade risk uses the app setting (${widget.analysisController.riskPercent.toStringAsFixed(1)}%) and live Bitunix equity; leverage changes required margin, not planned stop loss.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _numberRow({
    required String label,
    required String value,
    required bool enabled,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton.filledTonal(
            onPressed: enabled ? onMinus : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 72,
            child: Text(
              value,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton.filledTonal(
            onPressed: enabled ? onPlus : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _showServerConfiguration() async {
    final urlController = TextEditingController();
    final tokenController = TextEditingController();
    var tokenVisible = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_t('اتصال سرور اجرای ترید', 'Connect execution server')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlController,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'HTTPS Server URL',
                      hintText: 'https://trade.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tokenController,
                    textDirection: TextDirection.ltr,
                    obscureText: !tokenVisible,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Control Token',
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => tokenVisible = !tokenVisible,
                        ),
                        icon: Icon(
                          tokenVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      'توکن داخل Secure Storage گوشی می‌ماند. کلید Bitunix را در چت، GitHub یا لاگ قرار نده.',
                      'The token remains in device secure storage. Never place the Bitunix secret in chat, GitHub, or logs.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_t('لغو', 'Cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  final connected = await widget.controller.configure(
                    baseUrl: urlController.text,
                    controlToken: tokenController.text,
                  );
                  if (connected && dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  } else if (dialogContext.mounted) {
                    setDialogState(() {});
                  }
                },
                child: Text(_t('تست و ذخیره', 'Test & save')),
              ),
            ],
          ),
        ),
      );
    } finally {
      urlController.dispose();
      tokenController.dispose();
    }
  }

  Future<void> _confirmStart() async {
    final strategy = widget.analysisController.strategy.name;
    final configuration = UnattendedRunConfiguration(
      allowedSymbols: _enabledSymbols.toList(growable: false),
      allowedStrategies: [strategy],
      allowedTimeframes: _enabledTimeframes.toList(growable: false),
      globalLeverage: _leverage,
      riskPerTradePercent: widget.analysisController.riskPercent,
      maximumDailyLossPercent: _dailyLossLimit,
      maximumWeeklyLossPercent: math.max(_dailyLossLimit, 5),
      maximumConcurrentPositions: _maximumPositions,
      maximumMarginUsagePercent: 35,
      maximumCorrelatedExposurePercent: 50,
      maximumSlippagePercent: 0.2,
      maximumSignalAgeSeconds: 1200,
    );
    final errors = configuration.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errors.join('\n'))),
      );
      return;
    }
    if (!widget.accountController.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'ابتدا اتصال حساب Bitunix و موجودی را در همین تب تأیید کن.',
              'Connect and verify the Bitunix account in this tab first.',
            ),
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('شروع اجرای خودکار؟', 'Start unattended trading?')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('پس از شروع، سرور بدون نیاز به بازبودن اپ کار می‌کند.', 'After Start, the server runs without the app remaining open.')),
              const SizedBox(height: 12),
              Text('${_t('نمادها', 'Symbols')}: ${_enabledSymbols.join(', ')}', textDirection: TextDirection.ltr),
              Text('${_t('تایم‌فریم‌ها', 'Timeframes')}: ${_enabledTimeframes.join(', ')}', textDirection: TextDirection.ltr),
              Text('${_t('اهرم', 'Leverage')}: ${_leverage}x'),
              Text('${_t('ریسک هر معامله', 'Risk per trade')}: ${widget.analysisController.riskPercent.toStringAsFixed(1)}%'),
              Text('${_t('سقف ضرر روزانه', 'Daily loss limit')}: ${_dailyLossLimit.toStringAsFixed(1)}%'),
              Text('${_t('حداکثر پوزیشن', 'Maximum positions')}: $_maximumPositions'),
              const SizedBox(height: 12),
              Text(
                _t(
                  'شروع فقط در صورت سلامت WebSocket خصوصی، داده تازه، مارجین ایزوله و امکان تأیید استاپ حفاظتی پذیرفته می‌شود.',
                  'Start is accepted only with a healthy private WebSocket, fresh data, isolated margin, and verifiable protective stops.',
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('لغو', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(_t('تأیید و شروع', 'Confirm & start')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.start(configuration);
  }

  Future<void> _confirmStop() async {
    final policy = await showDialog<UnattendedStopPolicy>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('نحوه قطع ترید', 'Stop policy')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(_t('توقف ورودهای جدید', 'Stop new entries')),
              subtitle: Text(
                _t(
                  'پوزیشن‌های موجود با استاپ و TP مدیریت شوند تا بسته شوند.',
                  'Keep protecting and managing existing positions until terminal exits.',
                ),
              ),
              onTap: () => Navigator.pop(
                context,
                UnattendedStopPolicy.protectAndManage,
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.emergency_outlined,
                color: QuantaraColors.danger,
              ),
              title: Text(_t('بستن اضطراری', 'Emergency close')),
              subtitle: Text(
                _t(
                  'ورودی‌ها لغو و پوزیشن‌های متعلق به Quantara با Reduce-only بسته شوند.',
                  'Cancel entries and reduce-only close Quantara-owned positions.',
                ),
              ),
              onTap: () => Navigator.pop(
                context,
                UnattendedStopPolicy.emergencyReduceOnlyClose,
              ),
            ),
          ],
        ),
      ),
    );
    if (policy == null) return;
    final snapshot = widget.accountController.snapshot;
    await widget.controller.stop(
      policy: policy,
      hasOpenPositionsOrOrders:
          snapshot != null &&
          (snapshot.positions.isNotEmpty || snapshot.orders.isNotEmpty),
    );
  }

  String _stateLabel(UnattendedRunState? state) => switch (state) {
    UnattendedRunState.armed => _t('فعال', 'Armed'),
    UnattendedRunState.arming => _t('در حال شروع', 'Arming'),
    UnattendedRunState.paused => _t('متوقف موقت', 'Paused'),
    UnattendedRunState.circuitBreaker => _t('مدار ایمنی', 'Circuit breaker'),
    UnattendedRunState.stopping => _t('در حال قطع', 'Stopping'),
    UnattendedRunState.managingExistingPositions =>
      _t('فقط مدیریت پوزیشن‌ها', 'Managing positions'),
    UnattendedRunState.disarmed => _t('خاموش', 'Disarmed'),
    UnattendedRunState.unavailable || null => _t('نامشخص', 'Unavailable'),
  };
}

class _BoundaryNotice extends StatelessWidget {
  const _BoundaryNotice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color),
          const SizedBox(width: 9),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
