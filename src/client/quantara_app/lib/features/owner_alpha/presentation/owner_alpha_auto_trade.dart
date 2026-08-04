part of 'owner_alpha_page.dart';

class _AutoTradeView extends StatefulWidget {
  const _AutoTradeView({
    required this.controller,
    required this.unattendedController,
    required this.analysisController,
  });

  final AutoTradeController controller;
  final UnattendedAutoTradeController unattendedController;
  final OwnerAlphaController analysisController;

  @override
  State<_AutoTradeView> createState() => _AutoTradeViewState();
}

class _AutoTradeViewState extends State<_AutoTradeView>
    with WidgetsBindingObserver {
  late final LocalLiveTradeController _localController =
      LocalLiveTradeController(accountController: widget.controller);

  bool get _fa => Directionality.of(context) == TextDirection.rtl;

  String _t(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      widget.controller.reconcile(
        reason: PrivateAccountRefreshReason.accountPageOpened,
        force: true,
      ),
    );
    unawaited(_localController.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      widget.controller.reconcile(
        reason: PrivateAccountRefreshReason.appResume,
        force: true,
      ),
    );
    unawaited(_localController.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localController.dispose();
    super.dispose();
  }

  Future<void> _showConnectionDialog() async {
    final apiKeyController = TextEditingController();
    final secretController = TextEditingController();
    var secretVisible = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_t('اتصال حساب Bitunix', 'Connect Bitunix')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      'کلید باید دسترسی مشاهده و ترید فیوچرز داشته باشد؛ دسترسی برداشت یا انتقال وجه را هرگز فعال نکن.',
                      'The key may have futures read and trade permission, but must never have withdrawal or transfer permission.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: apiKeyController,
                    autofocus: true,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secretController,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: !secretVisible,
                    decoration: InputDecoration(
                      labelText: 'API Secret',
                      prefixIcon: const Icon(Icons.password_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => secretVisible = !secretVisible,
                        ),
                        icon: Icon(
                          secretVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      'اطلاعات فقط پس از تست موفق در Secure Storage دستگاه ذخیره می‌شود و وارد لاگ، گیت‌هاب یا گزارش خطا نمی‌شود.',
                      'Credentials are stored in device secure storage only after a successful test and are excluded from logs, GitHub, and diagnostics.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: widget.controller.isBusy
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: Text(_t('لغو', 'Cancel')),
              ),
              FilledButton.icon(
                onPressed: widget.controller.isBusy
                    ? null
                    : () async {
                        final connected = await widget.controller.connect(
                          apiKey: apiKeyController.text,
                          secretKey: secretController.text,
                        );
                        if (connected && dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        } else if (dialogContext.mounted) {
                          setDialogState(() {});
                        }
                      },
                icon: widget.controller.isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(_t('تست و اتصال', 'Test & connect')),
              ),
            ],
          ),
        ),
      );
    } finally {
      apiKeyController.dispose();
      secretController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.unattendedController,
        _localController,
      ]),
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LocalLiveTradeControlCard(
              controller: _localController,
              accountController: widget.controller,
              analysisController: widget.analysisController,
            ),
            const SizedBox(height: 16),
            _LockedServerModeCard(
              legacyConfigured: widget.unattendedController.isConfigured,
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              QuantaraColors.violet,
                              QuantaraColors.cyan,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: QuantaraColors.ink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('حساب Bitunix', 'Bitunix account'),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              _t(
                                'اتصال امن، موجودی، پوزیشن‌ها و سفارش‌های فعال',
                                'Secure connection, balance, positions, and open orders',
                              ),
                            ),
                          ],
                        ),
                      ),
                      _connectionPill(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _BoundaryNotice(
                    text: _t(
                      'فعال‌کردن ترید محلی به معنی تضمین اجرای شبانه نیست. اگر گوشی Force Stop، خاموش، بدون اینترنت یا توسط Android متوقف شود، ورود جدید انجام نمی‌شود؛ SL و TP ثبت‌شده در خود صرافی مستقل باقی می‌مانند.',
                      'Local live mode is not a guarantee of overnight execution. Force-stop, reboot, connectivity loss, or Android suspension blocks new entries; already-confirmed exchange SL/TP orders remain independent.',
                    ),
                    color: QuantaraColors.warning,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (widget.controller.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SectionCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: QuantaraColors.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(widget.controller.error!)),
                    ],
                  ),
                ),
              ),
            if (!widget.controller.isConnected || snapshot == null)
              _DisconnectedAccountCard(
                busy: widget.controller.isBusy,
                onConnect: _showConnectionDialog,
              )
            else ...[
              if (widget.controller.reconciliation.health !=
                  PrivateAccountReconciliationHealth.fresh) ...[
                PrivateAccountReconciliationBanner(
                  state: widget.controller.reconciliation,
                  persian: _fa,
                ),
                const SizedBox(height: 12),
              ],
              _AccountOverviewCard(
                snapshot: snapshot,
                reconciliation: widget.controller.reconciliation,
                maskedApiKey: widget.controller.maskedApiKey ?? '••••••••',
                onRefresh: widget.controller.isBusy
                    ? null
                    : widget.controller.refresh,
                onDisconnect:
                    widget.controller.isBusy || _localController.isRunning
                    ? null
                    : () => _confirmDisconnect(),
              ),
              const SizedBox(height: 16),
              _AutoTradeUniversePreview(
                symbols: widget.analysisController.symbols,
              ),
              const SizedBox(height: 16),
              _OpenPositionsCard(
                snapshot: snapshot,
                reconciliation: widget.controller.reconciliation,
              ),
              const SizedBox(height: 16),
              _OpenOrdersCard(snapshot: snapshot),
            ],
            const SizedBox(height: 16),
            _AutoTradeSafetyRoadmap(connected: widget.controller.isConnected),
          ],
        );
      },
    );
  }

  Widget _connectionPill() {
    return switch (widget.controller.state) {
      AutoTradeConnectionState.connecting => StatusPill(
        label: _t('در حال اتصال', 'Connecting'),
        color: QuantaraColors.warning,
        icon: Icons.sync_rounded,
      ),
      AutoTradeConnectionState.readOnly => StatusPill(
        label: _t('متصل', 'Connected'),
        color: QuantaraColors.success,
        icon: Icons.verified_user_outlined,
      ),
      AutoTradeConnectionState.error => StatusPill(
        label: _t('خطا', 'Error'),
        color: QuantaraColors.danger,
        icon: Icons.error_outline_rounded,
      ),
      AutoTradeConnectionState.disconnected => StatusPill(
        label: _t('قطع', 'Disconnected'),
        color: QuantaraColors.warning,
        icon: Icons.link_off_rounded,
      ),
    };
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('قطع اتصال', 'Disconnect account')),
        content: Text(
          _t(
            'کلید و Secret ذخیره‌شده از Secure Storage این دستگاه حذف شود؟',
            'Remove the saved API key and secret from this device secure storage?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('حذف و قطع', 'Remove & disconnect')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.disconnect();
  }
}

class _LocalLiveTradeControlCard extends StatefulWidget {
  const _LocalLiveTradeControlCard({
    required this.controller,
    required this.accountController,
    required this.analysisController,
  });

  final LocalLiveTradeController controller;
  final AutoTradeController accountController;
  final OwnerAlphaController analysisController;

  @override
  State<_LocalLiveTradeControlCard> createState() =>
      _LocalLiveTradeControlCardState();
}

class _LocalLiveTradeControlCardState
    extends State<_LocalLiveTradeControlCard> {
  final LocalLivePreferencesStore _preferencesStore =
      const SharedPreferencesLocalLivePreferencesStore();
  final Set<String> _enabledSymbols = {};
  final Set<String> _enabledTimeframes = {'1h', '4h'};
  int _leverage = 10;
  double _riskPercent = 0.10;
  double _dailyLossLimit = 1;
  int _maximumConcurrentPositions = 2;
  int _tp1Percent = 65;
  int _tp2Percent = 20;
  int _tp3Percent = 15;
  bool _preferencesLoaded = false;

  bool get _fa => Directionality.of(context) == TextDirection.rtl;

  String _t(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _enabledSymbols.addAll(widget.analysisController.symbols.take(4));
    unawaited(_restorePreferences());
  }

  Future<void> _restorePreferences() async {
    try {
      final value = await _preferencesStore
          .load(availableSymbols: widget.analysisController.symbols)
          .timeout(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        _enabledSymbols
          ..clear()
          ..addAll(value.symbols);
        _enabledTimeframes
          ..clear()
          ..addAll(value.timeframes);
        _leverage = value.leverage;
        _riskPercent = value.riskPercent;
        _dailyLossLimit = value.dailyLossLimitPercent;
        _maximumConcurrentPositions = value.maximumConcurrentPositions;
        _tp1Percent = (value.targetAllocation.tp1Fraction * 100).round();
        _tp2Percent = (value.targetAllocation.tp2Fraction * 100).round();
        _tp3Percent = 100 - _tp1Percent - _tp2Percent;
        _preferencesLoaded = true;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _preferencesLoaded = true);
    }
  }

  LocalLivePreferences get _currentPreferences => LocalLivePreferences(
    symbols: _enabledSymbols.toList(growable: false),
    timeframes: Set.unmodifiable(_enabledTimeframes),
    leverage: _leverage,
    riskPercent: _riskPercent,
    dailyLossLimitPercent: _dailyLossLimit,
    maximumConcurrentPositions: _maximumConcurrentPositions,
    targetAllocation: _targetAllocation,
  ).normalized(widget.analysisController.symbols);

  ProfitProtectionTargetAllocation get _targetAllocation =>
      ProfitProtectionTargetAllocation.checked(
        tp1Fraction: _tp1Percent / 100,
        tp2Fraction: _tp2Percent / 100,
        tp3Fraction: _tp3Percent / 100,
      );

  void _mutateAndSave(VoidCallback mutation) {
    setState(mutation);
    unawaited(_preferencesStore.save(_currentPreferences));
  }

  Future<void> _persistPreferences() =>
      _preferencesStore.save(_currentPreferences);

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.status;
    final serviceActive = status.isRunning;
    final entriesActive =
        status.state == LocalLiveTradeState.running && status.entriesEnabled;
    final canResumeEntries = status.canResumeEntries;
    final phaseOneQuarantine = !ExchangeTruthPhaseOneGate.realEntriesAllowed;
    final hasExistingPosition =
        widget.accountController.snapshot?.positions.isNotEmpty ?? false;
    final phaseOneStartBlocked = phaseOneQuarantine && !hasExistingPosition;
    final starting = status.state == LocalLiveTradeState.starting;
    final breaker = status.state == LocalLiveTradeState.circuitBreaker;
    final color = breaker
        ? QuantaraColors.danger
        : entriesActive
        ? QuantaraColors.success
        : serviceActive
        ? QuantaraColors.warning
        : QuantaraColors.cyan;
    final localizedStatus = LocalLiveMessageLocalizer.localize(
      status.message,
      persian: _fa,
    );
    return SectionCard(
      accentColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  entriesActive
                      ? Icons.play_circle_fill_rounded
                      : serviceActive
                      ? Icons.pause_circle_filled_rounded
                      : Icons.phone_android_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        'ترید واقعی محلی · Canary',
                        'Guarded local live · Canary',
                      ),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _t(
                        'اجرا روی همین گوشی با سرویس دائماً قابل‌مشاهده Android',
                        'Runs on this phone through a visible Android foreground service',
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: _stateLabel(status.state),
                color: color,
                icon: entriesActive
                    ? Icons.shield_rounded
                    : serviceActive
                    ? Icons.pause_circle_outline_rounded
                    : Icons.stop_circle_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BoundaryNotice(
            text: _t(
              'این حالت می‌تواند سفارش واقعی فیوچرز ارسال کند. حداکثر سه پوزیشن Isolated فقط در محدوده بودجه اتمیک ریسک و مارجین پرتفوی مجاز است؛ هر ورود همچنان باید با SL کامل و سه TP تأییدشده صرافی محافظت شود.',
              'This mode can submit real futures orders. Up to three isolated positions are allowed only inside the atomic portfolio risk and margin budget; every entry still requires a full exchange-confirmed stop and three targets.',
            ),
            color: QuantaraColors.danger,
          ),
          if (!ExchangeTruthPhaseOneGate.realEntriesAllowed) ...[
            const SizedBox(height: 10),
            _BoundaryNotice(
              text: _t(
                'قرنطینه Phase 1 فعال است: ورود واقعی جدید کاملاً غیرفعال است. فقط در صورت وجود پوزیشن فعلی، سرویس می‌تواند در حالت مدیریت و تطبیق بدون Entry شروع شود.',
                'Phase 1 quarantine is active: every new real entry is disabled. The service may start only in management-only reconciliation mode when an existing position is present.',
              ),
              color: QuantaraColors.warning,
            ),
          ],
          if (widget.accountController.reconciliation.blocksNewEntries) ...[
            const SizedBox(height: 10),
            _BoundaryNotice(
              text: _t(
                'ورود واقعی تا همگام‌سازی تازه و بدون تناقض حساب Bitunix قفل است. مدیریت پوزیشن و حفاظت‌های موجود متوقف نمی‌شود.',
                'Real entries are locked until Bitunix private-account truth is fresh and coherent. Existing position and protection management continues.',
              ),
              color: QuantaraColors.warning,
            ),
          ],
          if (widget.controller.error != null) ...[
            const SizedBox(height: 10),
            _LocalLiveStatusNotice(
              message: widget.controller.error!,
              persian: _fa,
              error: true,
            ),
          ],
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: QuantaraMotion.fast,
            child: Text(
              localizedStatus,
              key: ValueKey(localizedStatus),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (canResumeEntries) ...[
            const SizedBox(height: 10),
            _BoundaryNotice(
              text: _t(
                'ورود جدید متوقف است و هیچ پوزیشن بازی برای مدیریت وجود ندارد. برای فعال‌سازی دوباره، دکمه «ازسرگیری ورود» را بزن و همه تأییدهای پول واقعی را دوباره انجام بده.',
                'New entries are stopped and there is no open position to manage. Use Resume entries and repeat every real-money confirmation to arm entries again.',
              ),
              color: QuantaraColors.warning,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: _t(
                  '${status.openPositionCount}/$_maximumConcurrentPositions پوزیشن باز',
                  '${status.openPositionCount}/$_maximumConcurrentPositions open',
                ),
                color: status.openPositionCount > 0
                    ? QuantaraColors.warning
                    : QuantaraColors.cyan,
              ),
              StatusPill(
                label: status.effectiveSessionNetPnl == null
                    ? _t('خالص جلسه: ناموجود', 'Session net: unavailable')
                    : '${status.effectiveSessionNetPnl! >= 0 ? '+' : ''}${status.effectiveSessionNetPnl!.toStringAsFixed(2)} USDT',
                color: status.effectiveSessionNetPnl == null
                    ? QuantaraColors.warning
                    : status.effectiveSessionNetPnl! >= 0
                    ? QuantaraColors.success
                    : QuantaraColors.danger,
              ),
              if (status.pnlProjection != null)
                StatusPill(
                  label: status.pnlProjection!.accountUnrealized.isAvailable
                      ? _t(
                          'باز ${_pnlMetricText(status.pnlProjection!.accountUnrealized)}',
                          'Open ${_pnlMetricText(status.pnlProjection!.accountUnrealized)}',
                        )
                      : _t('باز: ناموجود', 'Open: unavailable'),
                  color:
                      _pnlMetricColor(
                        status.pnlProjection!.accountUnrealized,
                      ) ??
                      QuantaraColors.warning,
                ),
              StatusPill(
                label: _t(
                  '${status.closedPositionCount} بسته',
                  '${status.closedPositionCount} closed',
                ),
                color: QuantaraColors.violet,
              ),
            ],
          ),
          const Divider(height: 28),
          if (!_preferencesLoaded) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          AbsorbPointer(
            absorbing:
                serviceActive ||
                widget.controller.isBusy ||
                !_preferencesLoaded,
            child: Opacity(
              opacity: serviceActive ? 0.60 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('نمادهای مجاز', 'Allowed symbols'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final symbol in widget.analysisController.symbols)
                        FilterChip(
                          avatar: SymbolAvatar(
                            symbol: symbol,
                            size: 22,
                            showBorder: false,
                          ),
                          label: Text(symbol, textDirection: TextDirection.ltr),
                          selected: _enabledSymbols.contains(symbol),
                          onSelected: (selected) => _mutateAndSave(() {
                            if (selected) {
                              _enabledSymbols.add(symbol);
                            } else {
                              _enabledSymbols.remove(symbol);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _t('تایم‌فریم‌های مجاز', 'Allowed timeframes'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final timeframe in const ['5m', '15m', '1h', '4h'])
                        FilterChip(
                          label: Text(
                            timeframe,
                            textDirection: TextDirection.ltr,
                          ),
                          selected: _enabledTimeframes.contains(timeframe),
                          onSelected: (selected) => _mutateAndSave(() {
                            if (selected) {
                              _enabledTimeframes.add(timeframe);
                            } else {
                              _enabledTimeframes.remove(timeframe);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _numberRow(
                    label: _t('اهرم عمومی', 'Global leverage'),
                    value: '${_leverage}x',
                    onMinus: () => _mutateAndSave(
                      () => _leverage = math.max(1, _leverage - 1),
                    ),
                    onPlus: () => _mutateAndSave(
                      () => _leverage = math.min(125, _leverage + 1),
                    ),
                  ),
                  _numberRow(
                    label: _t('ریسک هر معامله', 'Risk per trade'),
                    value: '${_riskPercent.toStringAsFixed(2)}%',
                    onMinus: () => _mutateAndSave(() {
                      final step = _riskPercent > 0.50 ? 0.25 : 0.05;
                      _riskPercent = math.max(0.05, _riskPercent - step);
                    }),
                    onPlus: () => _mutateAndSave(() {
                      final step = _riskPercent >= 0.50 ? 0.25 : 0.05;
                      _riskPercent = math.min(2.0, _riskPercent + step);
                    }),
                  ),
                  _numberRow(
                    label: _t('سقف ضرر روزانه', 'Daily loss cap'),
                    value: '${_dailyLossLimit.toStringAsFixed(2)}%',
                    onMinus: () => _mutateAndSave(() {
                      final step = _dailyLossLimit > 3 ? 1.0 : 0.25;
                      _dailyLossLimit = math.max(0.25, _dailyLossLimit - step);
                    }),
                    onPlus: () => _mutateAndSave(() {
                      final step = _dailyLossLimit >= 3 ? 1.0 : 0.25;
                      _dailyLossLimit = math.min(10, _dailyLossLimit + step);
                    }),
                  ),
                  _numberRow(
                    label: _t(
                      'حداکثر پوزیشن هم‌زمان',
                      'Maximum concurrent positions',
                    ),
                    value: _maximumConcurrentPositions.toString(),
                    onMinus: () => _mutateAndSave(
                      () => _maximumConcurrentPositions = math.max(
                        1,
                        _maximumConcurrentPositions - 1,
                      ),
                    ),
                    onPlus: () => _mutateAndSave(
                      () => _maximumConcurrentPositions = math.min(
                        3,
                        _maximumConcurrentPositions + 1,
                      ),
                    ),
                  ),
                  TpAllocationEditor(
                    allocation: _targetAllocation,
                    persian: _fa,
                    onChanged: (allocation) => _mutateAndSave(() {
                      _tp1Percent = (allocation.tp1Fraction * 100).round();
                      _tp2Percent = (allocation.tp2Fraction * 100).round();
                      _tp3Percent = 100 - _tp1Percent - _tp2Percent;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _BoundaryNotice(
                    text: _t(
                      'جمع سه هدف همیشه ۱۰۰٪ است. پس از تأیید کامل Fill هدف اول توسط Bitunix، استاپ باقی‌مانده فقط رو به سود و با احتساب هزینه‌ها منتقل می‌شود؛ کاهش صرف Quantity هیچ‌وقت محرک این تغییر نیست.',
                      'The three targets always total 100%. Only a complete Bitunix-confirmed TP1 fill may promote the remaining stop toward cost-aware profit; quantity reduction alone never triggers it.',
                    ),
                    color: QuantaraColors.cyan,
                  ),
                  if (_riskPercent > 0.50 ||
                      _dailyLossLimit > 3 ||
                      _leverage > 25) ...[
                    const SizedBox(height: 8),
                    _BoundaryNotice(
                      text: _t(
                        'حالت پیشرفته فعال است. اهرم بالا فقط مارجین را کم می‌کند و فاصله لیکویید را کاهش می‌دهد؛ ریسک بالاتر مستقیماً زیان مجاز هر معامله را افزایش می‌دهد.',
                        'Advanced settings are active. Higher leverage reduces required margin but narrows liquidation distance; higher risk directly increases allowed loss per trade.',
                      ),
                      color: QuantaraColors.warning,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
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
                      widget.controller.isBusy ||
                          starting ||
                          breaker ||
                          widget
                              .accountController
                              .reconciliation
                              .blocksNewEntries ||
                          phaseOneStartBlocked ||
                          (serviceActive && !canResumeEntries)
                      ? null
                      : _confirmStart,
                  icon: widget.controller.isBusy
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    phaseOneQuarantine && hasExistingPosition
                        ? _t('شروع مدیریت', 'Start management')
                        : canResumeEntries
                        ? _t('ازسرگیری ورود', 'Resume entries')
                        : _t('شروع ترید', 'Start trading'),
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
                  onPressed: widget.controller.isBusy || !serviceActive
                      ? null
                      : _confirmStop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(
                    _t('قطع ترید', 'Stop trading'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              TextButton.icon(
                onPressed: widget.controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_t('به‌روزرسانی', 'Refresh')),
              ),
              TextButton.icon(
                onPressed: _showAudit,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(_t('گزارش اجرا', 'Execution log')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberRow({
    required String label,
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton.filledTonal(
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 82,
            child: Text(
              value,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton.filledTonal(
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmStart() async {
    if (!_preferencesLoaded) return;
    if (!widget.accountController.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'ابتدا حساب Bitunix را متصل و تست کن.',
              'Connect and validate Bitunix first.',
            ),
          ),
        ),
      );
      return;
    }
    if (_enabledSymbols.isEmpty || _enabledTimeframes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'حداقل یک نماد و یک تایم‌فریم انتخاب کن.',
              'Select at least one symbol and timeframe.',
            ),
          ),
        ),
      );
      return;
    }
    if (_riskPercent > 0.50 || _dailyLossLimit > 3 || _leverage > 25) {
      final advancedConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(_t('تأیید تنظیمات پرریسک', 'Confirm advanced risk')),
          content: Text(
            _t(
              'این تنظیمات می‌توانند زیان واقعی را سریع‌تر افزایش دهند. Quantara استاپ را دورتر نمی‌کند، بعد از ضرر ریسک را بالا نمی‌برد و هر ورود هم‌زمان را به بودجه اتمیک پرتفوی محدود می‌کند. ادامه می‌دهی؟',
              'These settings can increase real losses faster. Quantara will not widen stops or increase risk after losses, and every concurrent entry remains constrained by the atomic portfolio budget. Continue?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('بازگشت', 'Go back')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: QuantaraColors.danger,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('ریسک را می‌پذیرم', 'I accept the risk')),
            ),
          ],
        ),
      );
      if (advancedConfirmed != true || !mounted) return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_t('فعال‌سازی پول واقعی', 'Enable real-money canary')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  'Quantara اجازه ارسال سفارش واقعی فیوچرز خواهد داشت. شروع فقط از همین صفحه انجام می‌شود و بعد از ری‌استارت گوشی خودکار فعال نمی‌شود.',
                  'Quantara will be allowed to submit real futures orders. It starts only from this visible screen and never auto-arms after a device reboot.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${_t('نمادها', 'Symbols')}: ${_enabledSymbols.join(', ')}',
                textDirection: TextDirection.ltr,
              ),
              Text('${_t('اهرم', 'Leverage')}: ${_leverage}x'),
              Text(
                '${_t('ریسک هر معامله', 'Risk per trade')}: ${_riskPercent.toStringAsFixed(2)}%',
              ),
              Text(
                '${_t('حد ضرر روزانه', 'Daily loss cap')}: ${_dailyLossLimit.toStringAsFixed(2)}%',
              ),
              Text(
                '${_t('حداکثر پوزیشن هم‌زمان', 'Maximum concurrent positions')}: $_maximumConcurrentPositions',
              ),
              Text(
                '${_t('تقسیم اهداف', 'Target allocation')}: TP1 $_tp1Percent% · TP2 $_tp2Percent% · TP3 $_tp3Percent%',
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 12),
              Text(
                _t(
                  'تأیید می‌کنم کلید API دسترسی برداشت/انتقال ندارد و اولین اجرا را با موجودی کم انجام می‌دهم.',
                  'I confirm the API key has no withdrawal/transfer permission and I will use a small balance for the first canary.',
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('تأیید و شروع', 'Confirm & start')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _persistPreferences();
    if (!mounted) return;
    final started = await widget.controller.start(
      LocalLiveTradeConfiguration(
        symbols: _enabledSymbols.toList(growable: false),
        timeframes: _enabledTimeframes.toList(growable: false),
        leverage: _leverage,
        riskPercent: _riskPercent,
        dailyLossLimitPercent: _dailyLossLimit,
        maximumConcurrentPositions: _maximumConcurrentPositions,
        strategy: widget.analysisController.strategy,
        cadence: widget.analysisController.cadence,
        languageCode: widget.analysisController.languageCode,
        targetAllocation: _targetAllocation,
      ),
    );
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalLiveMessageLocalizer.localize(
              widget.controller.error ??
                  _t('شروع امن انجام نشد.', 'Safe start was rejected.'),
              persian: _fa,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmStop() async {
    final policy = await showDialog<LocalLiveStopPolicy>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_t('قطع ترید محلی', 'Stop local trading')),
        content: Text(
          _t(
            'در حالت عادی ورود جدید متوقف و سرویس بسته می‌شود؛ SL و TP تأییدشده در Bitunix باقی می‌مانند. بستن اضطراری برای تمام پوزیشن‌های ساخته‌شده توسط Quantara سفارش Reduce-only ارسال می‌کند.',
            'Normal stop blocks new entries and stops the service while confirmed Bitunix SL/TP remains. Emergency close submits reduce-only closes for Quantara-managed positions.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('لغو', 'Cancel')),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(context, LocalLiveStopPolicy.protectAndStop),
            child: Text(_t('توقف عادی', 'Protect & stop')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: QuantaraColors.danger,
            ),
            onPressed: () =>
                Navigator.pop(context, LocalLiveStopPolicy.emergencyClose),
            child: Text(_t('بستن اضطراری', 'Emergency close')),
          ),
        ],
      ),
    );
    if (policy != null) await widget.controller.stop(policy);
  }

  Future<void> _showAudit() async {
    final events = await widget.controller.loadAudit();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: events.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t('هنوز رویدادی ثبت نشده.', 'No events recorded yet.'),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: events.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final event = events[index];
                  return ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(
                      LocalLiveMessageLocalizer.localize(
                        event.message,
                        persian: _fa,
                      ),
                    ),
                    subtitle: Text(
                      '${event.symbol ?? event.type} · ${event.at.toLocal()}',
                      textDirection: TextDirection.ltr,
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _stateLabel(LocalLiveTradeState state) => switch (state) {
    LocalLiveTradeState.stopped => _t('متوقف', 'Stopped'),
    LocalLiveTradeState.starting => _t('در حال شروع', 'Starting'),
    LocalLiveTradeState.running => _t('فعال', 'Running'),
    LocalLiveTradeState.managingOnly => _t('فقط مدیریت', 'Managing only'),
    LocalLiveTradeState.circuitBreaker => _t('مدار ایمنی', 'Circuit breaker'),
    LocalLiveTradeState.error => _t('خطا', 'Error'),
  };
}

class _LocalLiveStatusNotice extends StatelessWidget {
  const _LocalLiveStatusNotice({
    required this.message,
    required this.persian,
    this.error = false,
  });

  final String message;
  final bool persian;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final summary = LocalLiveMessageLocalizer.affordability(message);
    final localized = LocalLiveMessageLocalizer.localize(
      message,
      persian: persian,
    );
    final color = error ? QuantaraColors.danger : QuantaraColors.warning;
    if (summary == null) {
      return _BoundaryNotice(text: localized, color: color);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(QuantaraRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    persian
                        ? 'بررسی حداقل سرمایه لازم'
                        : 'Minimum capital check',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SymbolAvatar(symbol: summary.symbol, size: 34),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FinanceMetricPanel(
                  label: persian ? 'موجودی قابل استفاده' : 'Available margin',
                  value: '${summary.availableMargin} USDT',
                  icon: Icons.savings_outlined,
                  color: QuantaraColors.cyan,
                ),
                FinanceMetricPanel(
                  label: persian ? 'حداقل سرمایه' : 'Minimum floor',
                  value: '${summary.minimumMargin} USDT',
                  icon: Icons.vertical_align_top_rounded,
                  color: QuantaraColors.warning,
                ),
                FinanceMetricPanel(
                  label: persian ? 'کسری سرمایه' : 'Shortfall',
                  value: '${summary.shortfall} USDT',
                  icon: Icons.trending_down_rounded,
                  color: QuantaraColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              persian
                  ? 'محدودکننده فعلی ${summary.symbol} است. با توجه به فاصله حد ضرر، حجم سفارش و کنترل ریسک، ممکن است برای ورود واقعی سرمایه بیشتری لازم باشد.'
                  : '${summary.symbol} is currently the limiting symbol. Stop distance, order sizing and risk checks may require more capital.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedServerModeCard extends StatelessWidget {
  const _LockedServerModeCard({required this.legacyConfigured});

  final bool legacyConfigured;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
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
                  color: QuantaraColors.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.cloud_off_outlined,
                  color: QuantaraColors.violet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fa
                          ? 'ترید شبانه سروری · قفل'
                          : 'Always-on server trading · Locked',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      fa
                          ? 'برای اجرای مستقل از گوشی، خاموشی اپ و اینترنت موبایل'
                          : 'For execution independent from the phone and mobile connectivity',
                    ),
                  ],
                ),
              ),
              const StatusPill(
                label: 'LOCKED',
                color: QuantaraColors.violet,
                icon: Icons.lock_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BoundaryNotice(
            text: fa
                ? 'این بخش عمداً غیرفعال است تا Vault کلید، موتور همیشه‌روشن، مانیتورینگ، WebSocket خصوصی و تست Canary سرور مستقر شوند. هیچ دکمه Start سروری در این نسخه عمل نمی‌کند.'
                : 'This section is intentionally disabled until the credential vault, always-on worker, monitoring, private WebSocket, and server canary are deployed. No server Start action works in this release.',
            color: QuantaraColors.violet,
          ),
          if (legacyConfigured) ...[
            const SizedBox(height: 8),
            Text(
              fa
                  ? 'یک تنظیم قدیمی سرور روی دستگاه پیدا شد، اما تا بازشدن رسمی این قابلیت قابل استفاده نیست.'
                  : 'A legacy server configuration exists on this device, but it remains unusable until the feature is formally unlocked.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
