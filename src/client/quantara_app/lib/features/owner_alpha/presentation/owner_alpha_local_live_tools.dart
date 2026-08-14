part of 'owner_alpha_page.dart';

extension _LocalLiveIssue169Tools on _LocalLiveTradeControlCardState {
  String _strategyTitle(AnalysisStrategy strategy) => switch (strategy) {
    AnalysisStrategy.structureZones => _t(
      'ساختار تطبیقی بازار',
      'Adaptive market structure',
    ),
    AnalysisStrategy.trendPullback => _t('پولبک در روند', 'Trend pullback'),
    AnalysisStrategy.momentumContinuation => _t(
      'شکست، بازآزمایی و ادامه مومنتوم',
      'Breakout, retest & momentum',
    ),
  };

  String _strategyDescription(AnalysisStrategy strategy) => switch (strategy) {
    AnalysisStrategy.structureZones => _t(
      'حالت پیشنهادی: در بازار رونددار از ساختار کندل بسته‌شده و در بازار خنثی از برگشت محدوده استفاده می‌کند.',
      'Recommended: uses closed-candle structure in trends and range reversal in sideways markets.',
    ),
    AnalysisStrategy.trendPullback => _t(
      'ورود پس از اصلاح کنترل‌شده به ناحیه روند؛ برای بازارهای جهت‌دار مناسب‌تر است.',
      'Enters after a controlled retracement into trend structure; best suited to directional markets.',
    ),
    AnalysisStrategy.momentumContinuation => _t(
      'شکست معتبر، بازآزمایی و ادامه حرکت را بررسی می‌کند؛ ورود بدون تأیید بسته‌شدن کندل مجاز نیست.',
      'Looks for confirmed breakout, retest and continuation; no entry is accepted before candle-close confirmation.',
    ),
  };

  Widget _buildLocalLiveConfigurationSummary({required bool serviceActive}) {
    final preferences = _currentPreferences;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuantaraColors.cyan.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(QuantaraRadius.card),
        border: Border.all(color: QuantaraColors.cyan.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('تنظیمات ترید خودکار', 'Auto-trade settings'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        serviceActive
                            ? _t(
                                'سرویس فعال است؛ تنظیمات برای مشاهده باز می‌شوند و تا توقف سرویس قفل‌اند.',
                                'The service is active; settings open read-only until it is stopped.',
                              )
                            : _t(
                                'همه تنظیمات، نمادها و استراتژی‌ها داخل پنل چرخ‌دنده قرار دارند.',
                                'All symbols, strategies and risk controls are inside the gear panel.',
                              ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: _t('بازکردن تنظیمات', 'Open settings'),
                  onPressed: () =>
                      _showLocalLiveSettings(serviceActive: serviceActive),
                  icon: const Icon(Icons.settings_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                StatusPill(
                  label: _t(
                    '${preferences.symbols.length} نماد',
                    '${preferences.symbols.length} symbols',
                  ),
                  color: QuantaraColors.cyan,
                  icon: Icons.grid_view_rounded,
                ),
                StatusPill(
                  label: _t(
                    '${preferences.timeframes.length} تایم‌فریم',
                    '${preferences.timeframes.length} timeframes',
                  ),
                  color: QuantaraColors.violet,
                  icon: Icons.schedule_rounded,
                ),
                StatusPill(
                  label: _t(
                    '${preferences.strategies.length} استراتژی',
                    '${preferences.strategies.length} strategies',
                  ),
                  color: QuantaraColors.success,
                  icon: Icons.account_tree_outlined,
                ),
                StatusPill(
                  label:
                      '${preferences.leverage}x · ${preferences.riskPercent.toStringAsFixed(2)}%',
                  color: QuantaraColors.warning,
                  icon: Icons.speed_rounded,
                ),
                StatusPill(
                  label: _t(
                    'حداکثر ${preferences.maximumConcurrentPositions} پوزیشن',
                    'Max ${preferences.maximumConcurrentPositions} positions',
                  ),
                  color: QuantaraColors.cyan,
                  icon: Icons.layers_outlined,
                ),
                StatusPill(
                  label: 'TP $_tp1Percent / $_tp2Percent / $_tp3Percent',
                  color: QuantaraColors.violet,
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocalLiveSettings({required bool serviceActive}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final canEdit =
              !serviceActive && !widget.controller.isBusy && _preferencesLoaded;

          void mutate(VoidCallback mutation) {
            if (!canEdit) return;
            _mutateAndSave(mutation);
            setSheetState(() {});
          }

          return FractionallySizedBox(
            heightFactor: 0.92,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.settings_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _t('تنظیمات ترید واقعی محلی', 'Local Live settings'),
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(_t('تمام', 'Done')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!canEdit) ...[
                          _BoundaryNotice(
                            text: serviceActive
                                ? _t(
                                    'برای جلوگیری از تغییر پیکربندی وسط اجرای پول واقعی، تنظیمات تا توقف سرویس فقط خواندنی‌اند.',
                                    'To prevent configuration changes during real-money execution, settings are read-only until the service stops.',
                                  )
                                : _t(
                                    'تنظیمات هنوز در حال بازیابی هستند.',
                                    'Settings are still loading.',
                                  ),
                            color: QuantaraColors.warning,
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          _t('استراتژی‌های فعال', 'Enabled strategies'),
                          style: Theme.of(sheetContext).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            'هر استراتژی برای تمام نمادها و تایم‌فریم‌های انتخاب‌شده بررسی می‌شود. یک سیگنال ردشده دیگر جلوی بررسی بقیه را نمی‌گیرد.',
                            'Every enabled strategy is evaluated across all selected symbols and timeframes. A rejected setup no longer starves the remaining candidates.',
                          ),
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        for (final strategy in AnalysisStrategy.values)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _enabledStrategies.contains(strategy),
                            onChanged: !canEdit
                                ? null
                                : (selected) {
                                    if (selected != true &&
                                        _enabledStrategies.length == 1) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _t(
                                              'حداقل یک استراتژی باید فعال بماند.',
                                              'At least one strategy must remain enabled.',
                                            ),
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    mutate(() {
                                      if (selected == true) {
                                        _enabledStrategies.add(strategy);
                                      } else {
                                        _enabledStrategies.remove(strategy);
                                      }
                                    });
                                  },
                            title: Text(
                              _strategyTitle(strategy),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(_strategyDescription(strategy)),
                            secondary: Icon(switch (strategy) {
                              AnalysisStrategy.structureZones =>
                                Icons.hub_outlined,
                              AnalysisStrategy.trendPullback =>
                                Icons.trending_up_rounded,
                              AnalysisStrategy.momentumContinuation =>
                                Icons.rocket_launch_outlined,
                            }),
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed: !canEdit
                                ? null
                                : () => mutate(() {
                                    _enabledStrategies
                                      ..clear()
                                      ..addAll(
                                        LocalLivePreferences
                                            .recommendedStrategies,
                                      );
                                  }),
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: Text(
                              _t(
                                'بازگردانی حالت پیشنهادی',
                                'Restore recommended preset',
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 28),
                        Text(
                          _t('نمادهای مجاز', 'Allowed symbols'),
                          style: Theme.of(sheetContext).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            'تا ۳۰ نماد قابل انتخاب است. اسکن به‌صورت کنترل‌شده انجام می‌شود و سه پوزیشن فقط سقف هم‌زمانی است، نه هدف اجباری.',
                            'Up to 30 symbols may be selected. Scanning remains paced, and three positions is only a concurrency ceiling—not a forced target.',
                          ),
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final symbol
                                in widget.analysisController.symbols)
                              FilterChip(
                                avatar: SymbolAvatar(
                                  symbol: symbol,
                                  size: 22,
                                  showBorder: false,
                                ),
                                label: Text(
                                  symbol,
                                  textDirection: TextDirection.ltr,
                                ),
                                selected: _enabledSymbols.contains(symbol),
                                onSelected: !canEdit
                                    ? null
                                    : (selected) => mutate(() {
                                        if (selected) {
                                          if (_enabledSymbols.length <
                                              LocalLivePreferences
                                                  .maximumSymbolCount) {
                                            _enabledSymbols.add(symbol);
                                          }
                                        } else if (_enabledSymbols.length > 1) {
                                          _enabledSymbols.remove(symbol);
                                        }
                                      }),
                              ),
                          ],
                        ),
                        const Divider(height: 28),
                        Text(
                          _t('تایم‌فریم‌های مجاز', 'Allowed timeframes'),
                          style: Theme.of(sheetContext).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final timeframe in const [
                              '5m',
                              '15m',
                              '1h',
                              '4h',
                            ])
                              FilterChip(
                                label: Text(
                                  timeframe,
                                  textDirection: TextDirection.ltr,
                                ),
                                selected: _enabledTimeframes.contains(
                                  timeframe,
                                ),
                                onSelected: !canEdit
                                    ? null
                                    : (selected) => mutate(() {
                                        if (selected) {
                                          _enabledTimeframes.add(timeframe);
                                        } else if (_enabledTimeframes.length >
                                            1) {
                                          _enabledTimeframes.remove(timeframe);
                                        }
                                      }),
                              ),
                          ],
                        ),
                        const Divider(height: 28),
                        _numberRow(
                          label: _t('اهرم عمومی', 'Global leverage'),
                          value: '${_leverage}x',
                          onMinus: canEdit
                              ? () => mutate(
                                  () => _leverage = math.max(1, _leverage - 1),
                                )
                              : () {},
                          onPlus: canEdit
                              ? () => mutate(
                                  () =>
                                      _leverage = math.min(125, _leverage + 1),
                                )
                              : () {},
                        ),
                        _numberRow(
                          label: _t('ریسک هر معامله', 'Risk per trade'),
                          value: '${_riskPercent.toStringAsFixed(2)}%',
                          onMinus: canEdit
                              ? () => mutate(() {
                                  final step = _riskPercent > 0.50
                                      ? 0.25
                                      : 0.05;
                                  _riskPercent = math.max(
                                    0.05,
                                    _riskPercent - step,
                                  );
                                })
                              : () {},
                          onPlus: canEdit
                              ? () => mutate(() {
                                  final step = _riskPercent >= 0.50
                                      ? 0.25
                                      : 0.05;
                                  _riskPercent = math.min(
                                    2.0,
                                    _riskPercent + step,
                                  );
                                })
                              : () {},
                        ),
                        _numberRow(
                          label: _t('سقف ضرر روزانه', 'Daily loss cap'),
                          value: '${_dailyLossLimit.toStringAsFixed(2)}%',
                          onMinus: canEdit
                              ? () => mutate(() {
                                  final step = _dailyLossLimit > 3 ? 1.0 : 0.25;
                                  _dailyLossLimit = math.max(
                                    0.25,
                                    _dailyLossLimit - step,
                                  );
                                })
                              : () {},
                          onPlus: canEdit
                              ? () => mutate(() {
                                  final step = _dailyLossLimit >= 3
                                      ? 1.0
                                      : 0.25;
                                  _dailyLossLimit = math.min(
                                    10,
                                    _dailyLossLimit + step,
                                  );
                                })
                              : () {},
                        ),
                        _numberRow(
                          label: _t(
                            'حداکثر پوزیشن هم‌زمان',
                            'Maximum concurrent positions',
                          ),
                          value: _maximumConcurrentPositions.toString(),
                          onMinus: canEdit
                              ? () => mutate(
                                  () => _maximumConcurrentPositions = math.max(
                                    1,
                                    _maximumConcurrentPositions - 1,
                                  ),
                                )
                              : () {},
                          onPlus: canEdit
                              ? () => mutate(
                                  () => _maximumConcurrentPositions = math.min(
                                    3,
                                    _maximumConcurrentPositions + 1,
                                  ),
                                )
                              : () {},
                        ),
                        AbsorbPointer(
                          absorbing: !canEdit,
                          child: Opacity(
                            opacity: canEdit ? 1 : 0.58,
                            child: TpAllocationEditor(
                              allocation: _targetAllocation,
                              persian: _fa,
                              onChanged: (allocation) => mutate(() {
                                _tp1Percent = (allocation.tp1Fraction * 100)
                                    .round();
                                _tp2Percent = (allocation.tp2Fraction * 100)
                                    .round();
                                _tp3Percent = 100 - _tp1Percent - _tp2Percent;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _BoundaryNotice(
                          text: _t(
                            'هر ورود همچنان باید Isolated، داخل بودجه ریسک و مارجین، با استاپ کامل و پوشش تمام حجم توسط هدف‌های فعال تأییدشده صرافی باشد.',
                            'Every entry still must be isolated, inside risk and margin budgets, protected by a full stop, and cover the entire quantity with exchange-confirmed active targets.',
                          ),
                          color: QuantaraColors.cyan,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildManagedPositionTimeframes({
    required LocalLiveTradeStatus status,
    required List<AutoTradePosition> exchangePositions,
  }) {
    if (status.managedPositions.isEmpty && exchangePositions.isEmpty) {
      return const SizedBox.shrink();
    }
    final managedIds = status.managedPositions
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuantaraColors.violet.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(QuantaraRadius.card),
        border: Border.all(
          color: QuantaraColors.violet.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('پوزیشن‌های باز و تایم‌فریم', 'Open positions & timeframe'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final managed in status.managedPositions)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: SymbolAvatar(symbol: managed.symbol, size: 34),
                title: Text(
                  managed.symbol,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${managed.timeframe} · ${managed.direction == TradeDirection.long ? _t('خرید', 'Long') : _t('فروش', 'Short')}',
                  textDirection: TextDirection.ltr,
                ),
                trailing: StatusPill(
                  label: _t('تحت مدیریت', 'Managed'),
                  color: QuantaraColors.success,
                ),
              ),
            for (final position in exchangePositions)
              if (!managedIds.contains(position.positionId.trim()))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: SymbolAvatar(symbol: position.symbol, size: 34),
                  title: Text(
                    position.symbol,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _t(
                      'تایم‌فریم نامشخص · پوزیشن دستی یا بازیابی‌نشده',
                      'Unknown timeframe · manual or unrecovered position',
                    ),
                  ),
                  trailing: StatusPill(
                    label: _t('مدیریت‌نشده', 'Unmanaged'),
                    color: QuantaraColors.warning,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetailedLocalLiveAudit() async {
    final events = await widget.controller.loadAudit();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t('گزارش کامل اجرا', 'Full execution log'),
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _exportLocalLiveDiagnostics(events),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(_t('خروجی JSON', 'Export JSON')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Text(
                        _t(
                          'هنوز رویدادی ثبت نشده؛ خروجی تشخیصی همچنان وضعیت فعلی را شامل می‌شود.',
                          'No events are recorded yet; diagnostic export still includes current state.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          leading: const Icon(Icons.shield_outlined),
                          title: SelectableText(
                            LocalLiveMessageLocalizer.localizeAudit(
                              kind: event.type,
                              message: event.message,
                              persian: _fa,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              SelectableText(
                                '${event.type}\n${event.message}',
                                textDirection: TextDirection.ltr,
                              ),
                              const SizedBox(height: 5),
                              SelectableText(
                                '${event.symbol ?? '—'} · ${event.at.toLocal().toIso8601String()}',
                                textDirection: TextDirection.ltr,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportLocalLiveDiagnostics(
    List<LocalLiveAuditEvent> events,
  ) async {
    final generatedAt = DateTime.now().toUtc();
    try {
      final sections = await _buildLocalLiveDiagnosticSections(events);
      final json = LocalLiveDiagnosticBundle.encode(
        generatedAt: generatedAt,
        sections: sections,
      );
      final stamp = generatedAt.toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final fileName = 'quantara-local-live-diagnostics-$stamp.json';
      await SharePlus.instance.share(
        ShareParams(
          title: _t('گزارش تشخیصی Quantara', 'Quantara diagnostics'),
          subject: 'Quantara Local Live diagnostics',
          text: _t(
            'گزارش تشخیصی بدون کلید API و Secret برای بررسی مشکل.',
            'Secret-free diagnostic bundle for troubleshooting.',
          ),
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(json)),
              mimeType: 'application/json',
            ),
          ],
          fileNameOverrides: [fileName],
          downloadFallbackEnabled: true,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'ساخت یا اشتراک گزارش تشخیصی انجام نشد (${error.runtimeType}).',
              'Diagnostic bundle could not be created or shared (${error.runtimeType}).',
            ),
          ),
        ),
      );
    }
  }

  Map<String, Object?> _accountSnapshotDiagnostic(
    AutoTradeAccountSnapshot snapshot,
  ) => {
    'marginCoin': snapshot.marginCoin,
    'available': snapshot.available,
    'frozen': snapshot.frozen,
    'positionMargin': snapshot.positionMargin,
    'estimatedEquity': snapshot.estimatedEquity,
    'crossUnrealizedPnl': snapshot.crossUnrealizedPnl,
    'isolatedUnrealizedPnl': snapshot.isolatedUnrealizedPnl,
    'positionMode': snapshot.positionMode,
    'syncedAt': snapshot.syncedAt.toUtc().toIso8601String(),
    'positions': snapshot.positions
        .map(
          (item) => {
            'positionId': item.positionId,
            'symbol': item.symbol,
            'quantity': item.quantity,
            'side': item.side,
            'marginMode': item.marginMode,
            'positionMode': item.positionMode,
            'leverage': item.leverage,
            'margin': item.margin,
            'unrealizedPnl': item.unrealizedPnl,
            'liquidationPrice': item.liquidationPrice,
            'averageOpenPrice': item.averageOpenPrice,
            'realizedPnl': item.realizedPnl,
            'fee': item.fee,
            'funding': item.funding,
            'openedAt': item.openedAt?.toUtc().toIso8601String(),
          },
        )
        .toList(growable: false),
    'orders': snapshot.orders
        .map(
          (item) => {
            'orderId': item.orderId,
            'clientId': item.clientId,
            'symbol': item.symbol,
            'quantity': item.quantity,
            'filledQuantity': item.filledQuantity,
            'side': item.side,
            'orderType': item.orderType,
            'marginMode': item.marginMode,
            'leverage': item.leverage,
            'reduceOnly': item.reduceOnly,
          },
        )
        .toList(growable: false),
    'protectionOrders': snapshot.protectionOrders
        .map(
          (item) => {
            'exchangeId': item.exchangeId,
            'positionId': item.positionId,
            'symbol': item.symbol,
            'takeProfitPrice': item.takeProfitPrice,
            'takeProfitQuantity': item.takeProfitQuantity,
            'takeProfitStopType': item.takeProfitStopType,
            'takeProfitOrderType': item.takeProfitOrderType,
            'stopLossPrice': item.stopLossPrice,
            'stopLossQuantity': item.stopLossQuantity,
            'stopLossStopType': item.stopLossStopType,
            'stopLossOrderType': item.stopLossOrderType,
          },
        )
        .toList(growable: false),
    'protectionVerifications': snapshot.protectionVerifications.map(
      (key, value) => MapEntry(key, {
        'verified': value.verified,
        'asOf': value.asOf.toUtc().toIso8601String(),
        'reason': value.reason,
      }),
    ),
    'pnlProjection': snapshot.pnlProjection?.toJson(),
  };

  Future<T?> _storedValue<T>(String key) async {
    try {
      return await FlutterForegroundTask.getData<T>(key: key);
    } on Object {
      return null;
    }
  }

  Future<Object?> _storedJson(String key) async {
    final raw = await _storedValue<String>(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }
}

// AI Supervisor support-session transport — Issue #184.
final Expando<_SupervisorSupportUiState> _supervisorSupportUiStates =
    Expando<_SupervisorSupportUiState>();

final class _SupervisorSupportUiState {
  final manager = ReadOnlySupportSessionManager();
  final transport = const ReadOnlySupportSessionTransport();
  ReadOnlySupportSessionGrant? grant;
  ReadOnlySupportRemoteSnapshot? remote;
  Uri? baseUrl;
  bool busy = false;
  String? error;
}

extension _LocalLiveSupervisorSupportTools on _LocalLiveTradeControlCardState {
  _SupervisorSupportUiState get _supervisorSupportUi =>
      _supervisorSupportUiStates[this] ??= _SupervisorSupportUiState();

  Widget _buildSupervisorSupportSessionCard() {
    final state = _supervisorSupportUi;
    final local = state.manager.current;
    final remote = state.remote;
    final now = DateTime.now().toUtc();
    final active =
        local != null && remote != null && now.isBefore(remote.expiresAtUtc);
    final color = active ? QuantaraColors.success : QuantaraColors.violet;
    final endpoint = state.baseUrl?.resolve('/mcp/quantara');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(QuantaraRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.psychology_alt_outlined, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('ناظر هوشمند Quantara', 'Quantara AI Supervisor'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        _t(
                          'دسترسی موقت و فقط‌خواندنی ChatGPT به وضعیت، استراتژی، ریسک، ژورنال و خطاها؛ API Key و Secret هرگز ارسال نمی‌شوند.',
                          'Temporary read-only ChatGPT access to runtime, strategy, risk, journal and diagnostics; API keys and secrets are never sent.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: active ? _t('فعال', 'Active') : _t('خاموش', 'Off'),
                  color: color,
                  icon: active
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _BoundaryNotice(
              text: _t(
                'این اتصال هیچ مجوز ثبت/لغو سفارش، تغییر لوریج، SL/TP، انتقال وجه یا تغییر خودکار استراتژی زنده ندارد. Session حداکثر ۴۵ دقیقه فعال است و هر لحظه قابل لغو است.',
                'This connection has no authority to place/cancel orders, change leverage, SL/TP, transfer funds, or silently mutate live strategy. The session lasts at most 45 minutes and can be revoked at any time.',
              ),
              color: QuantaraColors.cyan,
            ),
            if (active && remote != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: '${remote.evidenceCount} evidence',
                    color: QuantaraColors.cyan,
                    icon: Icons.dataset_outlined,
                  ),
                  StatusPill(
                    label: 'ID ${remote.tokenFingerprint}',
                    color: QuantaraColors.violet,
                    icon: Icons.fingerprint_rounded,
                  ),
                  StatusPill(
                    label: _t(
                      'انقضا ${remote.expiresAtUtc.toLocal().hour.toString().padLeft(2, '0')}:${remote.expiresAtUtc.toLocal().minute.toString().padLeft(2, '0')}',
                      'Expires ${remote.expiresAtUtc.toLocal().hour.toString().padLeft(2, '0')}:${remote.expiresAtUtc.toLocal().minute.toString().padLeft(2, '0')}',
                    ),
                    color: QuantaraColors.warning,
                    icon: Icons.timer_outlined,
                  ),
                ],
              ),
              if (endpoint != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  endpoint.toString(),
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: QuantaraColors.danger),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: active
                  ? [
                      FilledButton.tonalIcon(
                        onPressed: state.busy
                            ? null
                            : _refreshSupervisorSupportSession,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(_t('تازه‌سازی شواهد', 'Refresh evidence')),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy || endpoint == null
                            ? null
                            : () => _copySupervisorConnection(endpoint),
                        icon: const Icon(Icons.link_rounded),
                        label: Text(_t('کپی MCP URL', 'Copy MCP URL')),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy || state.grant == null
                            ? null
                            : _copyTemporarySupportToken,
                        icon: const Icon(Icons.key_outlined),
                        label: Text(
                          _t('کپی توکن موقت', 'Copy temporary token'),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: state.busy
                            ? null
                            : _revokeSupervisorSupportSession,
                        icon: const Icon(Icons.link_off_rounded),
                        label: Text(_t('لغو دسترسی', 'Revoke access')),
                      ),
                    ]
                  : [
                      FilledButton.icon(
                        onPressed: state.busy
                            ? null
                            : _enableSupervisorSupportSession,
                        icon: state.busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.visibility_outlined),
                        label: Text(
                          _t(
                            'فعال‌سازی دسترسی ChatGPT',
                            'Enable ChatGPT access',
                          ),
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enableSupervisorSupportSession() async {
    final state = _supervisorSupportUi;
    setState(() {
      state.busy = true;
      state.error = null;
    });
    try {
      final serverConfig = await const SecureAutoTradeServerConfigStore()
          .load();
      if (serverConfig == null) {
        throw StateError(
          _t(
            'ابتدا تنظیمات سرور Quantara را در بخش سرور ثبت کن.',
            'Configure the Quantara server connection first.',
          ),
        );
      }
      final events = await widget.controller.loadAudit();
      final sections = await _buildLocalLiveDiagnosticSections(events);
      final grant = state.manager.enable(ttl: const Duration(minutes: 45));
      final fingerprint = state.manager.current!.tokenFingerprint;
      final evidence = ReadOnlySupportSessionEvidence.fromDiagnosticSections(
        bundleId: 'support-$fingerprint',
        observedAtUtc: DateTime.now().toUtc(),
        sections: sections,
      );
      if (evidence.isEmpty) {
        state.manager.revoke();
        throw StateError(
          _t('شواهد کافی ساخته نشد.', 'No reviewable evidence was produced.'),
        );
      }
      try {
        final remote = await state.transport.register(
          serverConfig: serverConfig,
          grant: grant,
          evidence: evidence,
        );
        if (!mounted) return;
        setState(() {
          state.grant = grant;
          state.remote = remote;
          state.baseUrl = serverConfig.baseUrl;
        });
      } on Object {
        state.manager.revoke();
        rethrow;
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        state.error = error is StateError
            ? error.message.toString()
            : _t(
                'فعال‌سازی Supervisor انجام نشد (${error.runtimeType}).',
                'Supervisor activation failed (${error.runtimeType}).',
              );
      });
    } finally {
      if (mounted) setState(() => state.busy = false);
    }
  }

  Future<void> _refreshSupervisorSupportSession() async {
    final state = _supervisorSupportUi;
    final grant = state.grant;
    final baseUrl = state.baseUrl;
    if (grant == null || baseUrl == null || state.manager.current == null) {
      return;
    }
    setState(() {
      state.busy = true;
      state.error = null;
    });
    try {
      final events = await widget.controller.loadAudit();
      final sections = await _buildLocalLiveDiagnosticSections(events);
      final fingerprint = state.manager.current!.tokenFingerprint;
      final evidence = ReadOnlySupportSessionEvidence.fromDiagnosticSections(
        bundleId: 'support-$fingerprint',
        observedAtUtc: DateTime.now().toUtc(),
        sections: sections,
      );
      final remote = await state.transport.refreshEvidence(
        baseUrl: baseUrl,
        supportToken: grant.token,
        evidence: evidence,
      );
      if (!mounted) return;
      setState(() => state.remote = remote);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        state.error = _t(
          'تازه‌سازی شواهد انجام نشد (${error.runtimeType}).',
          'Evidence refresh failed (${error.runtimeType}).',
        );
      });
    } finally {
      if (mounted) setState(() => state.busy = false);
    }
  }

  Future<void> _revokeSupervisorSupportSession() async {
    final state = _supervisorSupportUi;
    final grant = state.grant;
    final baseUrl = state.baseUrl;
    if (grant == null || baseUrl == null) return;
    setState(() {
      state.busy = true;
      state.error = null;
    });
    try {
      await state.transport.revoke(baseUrl: baseUrl, supportToken: grant.token);
      state.manager.revoke();
      if (!mounted) return;
      setState(() {
        state.grant = null;
        state.remote = null;
        state.baseUrl = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        state.error = _t(
          'لغو سمت سرور تأیید نشد؛ Session تا تأیید لغو یا زمان انقضا فعال فرض می‌شود (${error.runtimeType}).',
          'Server-side revoke was not confirmed; treat the session as active until revoke succeeds or it expires (${error.runtimeType}).',
        );
      });
    } finally {
      if (mounted) setState(() => state.busy = false);
    }
  }

  Future<void> _copySupervisorConnection(Uri endpoint) async {
    await Clipboard.setData(ClipboardData(text: endpoint.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('MCP URL کپی شد.', 'MCP URL copied.'))),
    );
  }

  Future<void> _copyTemporarySupportToken() async {
    final grant = _supervisorSupportUi.grant;
    if (grant == null) return;
    await Clipboard.setData(ClipboardData(text: grant.token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            'توکن موقت فقط برای اتصال read-only کپی شد؛ آن را عمومی نکن و بعد از تست دسترسی را لغو کن.',
            'Temporary read-only token copied. Keep it private and revoke access after testing.',
          ),
        ),
      ),
    );
  }

  Future<Map<String, Object?>> _buildLocalLiveDiagnosticSections(
    List<LocalLiveAuditEvent> events,
  ) async {
    final snapshot = widget.accountController.snapshot;
    final reconciliation = widget.accountController.reconciliation;
    final journalLedger = await DatabaseTradingJournalStore().load();
    final persisted = <String, Object?>{
      'configuration': await _storedJson(localLiveConfigurationKey),
      'status': await _storedJson(localLiveStatusKey),
      'managedPositions': await _storedJson(localLiveManagedPositionsKey),
      'pendingJournalClosures': await _storedJson(
        localLivePendingJournalClosuresKey,
      ),
      'executedSetupIds': await _storedJson(localLiveExecutedSetupIdsKey),
      'audit': await _storedJson(localLiveAuditKey),
      'sessionId': await _storedValue<String>(localLiveSessionIdKey),
      'sessionStartedAt': await _storedValue<String>(
        localLiveSessionStartedAtKey,
      ),
      'sessionPositionIds': await _storedJson(localLiveSessionPositionIdsKey),
      'sessionStartEquity': await _storedValue<double>(
        localLiveSessionStartEquityKey,
      ),
    };
    final preferences = _currentPreferences;
    return <String, Object?>{
      'configuration': <String, Object?>{
        'symbols': preferences.symbols,
        'timeframes': preferences.timeframes.toList(growable: false),
        'strategies': preferences.strategies
            .map((item) => item.name)
            .toList(growable: false),
        'leverage': preferences.leverage,
        'riskPercent': preferences.riskPercent,
        'dailyLossLimitPercent': preferences.dailyLossLimitPercent,
        'maximumConcurrentPositions': preferences.maximumConcurrentPositions,
        'targetAllocation': preferences.targetAllocation.toJson(),
        'cadence': widget.analysisController.cadence.name,
      },
      'localLiveStatus': widget.controller.status.toJson(),
      'privateAccountReconciliation': <String, Object?>{
        'health': reconciliation.health.name,
        'cycleId': reconciliation.cycleId,
        'completedAt': reconciliation.completedAt?.toUtc().toIso8601String(),
        'lastAttemptAt': reconciliation.lastAttemptAt
            ?.toUtc()
            .toIso8601String(),
        'refreshing': reconciliation.refreshing,
        'warning': reconciliation.warning,
        'localLiveOpenPositionCount': reconciliation.localLiveOpenPositionCount,
        'localLiveObservedAt': reconciliation.localLiveObservedAt
            ?.toUtc()
            .toIso8601String(),
      },
      'accountSnapshot': snapshot == null
          ? null
          : _accountSnapshotDiagnostic(snapshot),
      'analysisRuntime': <String, Object?>{
        'watchlist': widget.analysisController.symbols,
        'selectedSymbol': widget.analysisController.selectedSymbol,
        'selectedTimeframe': widget.analysisController.selectedTimeframe,
        'primaryStrategy': widget.analysisController.strategy.name,
        'cadence': widget.analysisController.cadence.name,
        'languageCode': widget.analysisController.languageCode,
      },
      'auditEvents': events
          .map((item) => item.toJson())
          .toList(growable: false),
      'tradingJournal': journalLedger.toJson(),
      'tradeEvidencePackets': TradingJournalEvidencePacketBuilder.buildAll(
        journalLedger,
      ),
      'supportSessionFoundation':
          ReadOnlySupportSessionManager.architectureDescriptor(),
      'persistedLocalServiceState': persisted,
    };
  }
}
