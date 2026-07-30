part of 'owner_alpha_page.dart';

class _AutoTradeView extends StatelessWidget {
  const _AutoTradeView({
    required this.controller,
    required this.analysisController,
  });

  final AutoTradeController controller;
  final OwnerAlphaController analysisController;

  bool _fa(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl;

  String _t(BuildContext context, String fa, String en) =>
      _fa(context) ? fa : en;

  Future<void> _showConnectionDialog(BuildContext context) async {
    final apiKeyController = TextEditingController();
    final secretController = TextEditingController();
    var secretVisible = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_t(context, 'اتصال حساب Bitunix', 'Connect Bitunix')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      context,
                      'این مرحله فقط خواندنی است و هیچ سفارشی ارسال نمی‌کند. کلید دارای دسترسی برداشت یا انتقال وجه نساز.',
                      'This phase is read-only and cannot place orders. Do not create a key with withdrawal or transfer access.',
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
                      context,
                      'اطلاعات فقط پس از تست موفق اتصال، در Secure Storage دستگاه ذخیره می‌شود و در لاگ یا GitHub نوشته نمی‌شود.',
                      'Credentials are saved in device secure storage only after a successful connection test and are never written to logs or GitHub.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: controller.isBusy
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: Text(_t(context, 'لغو', 'Cancel')),
              ),
              FilledButton.icon(
                onPressed: controller.isBusy
                    ? null
                    : () async {
                        final connected = await controller.connect(
                          apiKey: apiKeyController.text,
                          secretKey: secretController.text,
                        );
                        if (connected && dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        } else if (dialogContext.mounted) {
                          setDialogState(() {});
                        }
                      },
                icon: controller.isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(_t(context, 'تست و اتصال', 'Test & connect')),
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
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                          Icons.smart_toy_outlined,
                          color: QuantaraColors.ink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(context, 'ترید خودکار', 'Auto Trade'),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              _t(
                                context,
                                'محیط مستقل اتصال، ریسک و اجرای Bitunix',
                                'Dedicated Bitunix connection, risk, and execution workspace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      _connectionPill(context),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: QuantaraColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: QuantaraColors.warning.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          color: QuantaraColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _t(
                              context,
                              'نسخه 0.12A فقط خواندنی است. ثبت سفارش، تغییر اهرم صرافی و مدیریت خودکار پوزیشن تا عبور از Shadow Mode غیرفعال می‌ماند.',
                              'Version 0.12A is read-only. Order placement, exchange leverage changes, and autonomous position management stay disabled until Shadow Mode passes.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (controller.error != null)
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
                      Expanded(child: Text(controller.error!)),
                    ],
                  ),
                ),
              ),
            if (!controller.isConnected || snapshot == null)
              _DisconnectedAccountCard(
                busy: controller.isBusy,
                onConnect: () => _showConnectionDialog(context),
              )
            else ...[
              _AccountOverviewCard(
                snapshot: snapshot,
                maskedApiKey: controller.maskedApiKey ?? '••••••••',
                onRefresh: controller.isBusy ? null : controller.refresh,
                onDisconnect: controller.isBusy
                    ? null
                    : () => _confirmDisconnect(context),
              ),
              const SizedBox(height: 16),
              _AutoTradeUniversePreview(
                symbols: analysisController.symbols,
              ),
              const SizedBox(height: 16),
              _OpenPositionsCard(snapshot: snapshot),
              const SizedBox(height: 16),
              _OpenOrdersCard(snapshot: snapshot),
            ],
            const SizedBox(height: 16),
            _AutoTradeSafetyRoadmap(connected: controller.isConnected),
          ],
        );
      },
    );
  }

  Widget _connectionPill(BuildContext context) {
    return switch (controller.state) {
      AutoTradeConnectionState.connecting => StatusPill(
          label: _t(context, 'در حال اتصال', 'Connecting'),
          color: QuantaraColors.warning,
          icon: Icons.sync_rounded,
        ),
      AutoTradeConnectionState.readOnly => StatusPill(
          label: _t(context, 'فقط خواندنی', 'Read-only'),
          color: QuantaraColors.success,
          icon: Icons.verified_user_outlined,
        ),
      AutoTradeConnectionState.error => StatusPill(
          label: _t(context, 'خطا', 'Error'),
          color: QuantaraColors.danger,
          icon: Icons.error_outline_rounded,
        ),
      AutoTradeConnectionState.disconnected => StatusPill(
          label: _t(context, 'قطع', 'Disconnected'),
          color: QuantaraColors.warning,
          icon: Icons.link_off_rounded,
        ),
    };
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t(context, 'قطع اتصال', 'Disconnect account')),
        content: Text(
          _t(
            context,
            'کلید و Secret ذخیره‌شده از Secure Storage این دستگاه حذف شود؟',
            'Remove the saved API key and secret from this device secure storage?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t(context, 'لغو', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t(context, 'حذف و قطع', 'Remove & disconnect')),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.disconnect();
  }
}

class _DisconnectedAccountCard extends StatelessWidget {
  const _DisconnectedAccountCard({
    required this.busy,
    required this.onConnect,
  });

  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'حساب Bitunix متصل نیست' : 'Bitunix account is disconnected',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            fa
                ? 'برای دریافت موجودی، پوزیشن‌ها و سفارش‌های باز، API فقط خواندنی را وارد کن.'
                : 'Enter a read-only API credential to load balances, positions, and open orders.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : onConnect,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_link_rounded),
            label: Text(fa ? 'اتصال حساب' : 'Connect account'),
          ),
        ],
      ),
    );
  }
}

class _AccountOverviewCard extends StatelessWidget {
  const _AccountOverviewCard({
    required this.snapshot,
    required this.maskedApiKey,
    required this.onRefresh,
    required this.onDisconnect,
  });

  final AutoTradeAccountSnapshot snapshot;
  final String maskedApiKey;
  final Future<bool> Function()? onRefresh;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final pnlColor = snapshot.totalUnrealizedPnl >= 0
        ? QuantaraColors.success
        : QuantaraColors.danger;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fa ? 'خلاصه حساب فیوچرز' : 'Futures account overview',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: fa ? 'به‌روزرسانی' : 'Refresh',
                onPressed: onRefresh == null ? null : () => onRefresh!(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            'API: $maskedApiKey · ${snapshot.positionMode}',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 14,
            children: [
              MetricTile(
                label: fa ? 'موجودی آزاد' : 'Available',
                value: QuantaraNumberFormat.marketValue(
                  snapshot.available,
                  unit: snapshot.marginCoin,
                ),
                valueColor: QuantaraColors.success,
              ),
              MetricTile(
                label: fa ? 'ارزش برآوردی حساب' : 'Estimated equity',
                value: QuantaraNumberFormat.marketValue(
                  snapshot.estimatedEquity,
                  unit: snapshot.marginCoin,
                ),
              ),
              MetricTile(
                label: fa ? 'مارجین پوزیشن‌ها' : 'Position margin',
                value: QuantaraNumberFormat.marketValue(
                  snapshot.positionMargin,
                  unit: snapshot.marginCoin,
                ),
              ),
              MetricTile(
                label: fa ? 'سود/زیان باز' : 'Unrealized P/L',
                value: QuantaraNumberFormat.marketValue(
                  snapshot.totalUnrealizedPnl,
                  unit: snapshot.marginCoin,
                ),
                valueColor: pnlColor,
              ),
              MetricTile(
                label: fa ? 'پوزیشن باز' : 'Open positions',
                value: snapshot.positions.length.toString(),
              ),
              MetricTile(
                label: fa ? 'سفارش باز' : 'Open orders',
                value: snapshot.orders.length.toString(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${fa ? 'آخرین همگام‌سازی' : 'Last sync'}: ${snapshot.syncedAt.toLocal()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off_rounded),
            label: Text(fa ? 'قطع و حذف کلید' : 'Disconnect & remove key'),
          ),
        ],
      ),
    );
  }
}

class _AutoTradeUniversePreview extends StatelessWidget {
  const _AutoTradeUniversePreview({required this.symbols});

  final List<String> symbols;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fa ? 'نمادهای ترید خودکار' : 'Auto-trade universe',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              StatusPill(
                label: fa ? 'قفل تا Shadow' : 'Locked until Shadow',
                color: QuantaraColors.warning,
                icon: Icons.lock_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fa
                ? 'واچ‌لیست تحلیل به‌صورت خودکار مجوز معامله نمی‌گیرد. در مرحله بعد برای هر نماد، استراتژی و تایم‌فریم Allow-list مستقل می‌سازیم.'
                : 'The analysis watchlist never grants trading permission automatically. The next phase adds an explicit allow-list per symbol, strategy, and timeframe.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final symbol in symbols)
                InputChip(
                  label: Text(symbol, textDirection: TextDirection.ltr),
                  avatar: const Icon(Icons.lock_outline_rounded, size: 17),
                  onPressed: null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpenPositionsCard extends StatelessWidget {
  const _OpenPositionsCard({required this.snapshot});

  final AutoTradeAccountSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'پوزیشن‌های باز Bitunix' : 'Open Bitunix positions',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (snapshot.positions.isEmpty)
            Text(fa ? 'پوزیشن بازی وجود ندارد.' : 'No open positions.')
          else
            for (final position in snapshot.positions) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(position.symbol.substring(0, 1)),
                ),
                title: Text(
                  '${position.symbol} · ${position.side}',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(
                  '${position.marginMode} · ${position.leverage}x · Qty ${position.quantity}',
                  textDirection: TextDirection.ltr,
                ),
                trailing: Text(
                  QuantaraNumberFormat.marketValue(
                    position.unrealizedPnl,
                    unit: 'USDT',
                  ),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: position.unrealizedPnl >= 0
                        ? QuantaraColors.success
                        : QuantaraColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _OpenOrdersCard extends StatelessWidget {
  const _OpenOrdersCard({required this.snapshot});

  final AutoTradeAccountSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'سفارش‌های باز Bitunix' : 'Open Bitunix orders',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (snapshot.orders.isEmpty)
            Text(fa ? 'سفارش بازی وجود ندارد.' : 'No open orders.')
          else
            for (final order in snapshot.orders) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  '${order.symbol} · ${order.side} · ${order.orderType}',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(
                  'Qty ${order.filledQuantity}/${order.quantity} · ${order.leverage}x · ${order.marginMode}',
                  textDirection: TextDirection.ltr,
                ),
              ),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _AutoTradeSafetyRoadmap extends StatelessWidget {
  const _AutoTradeSafetyRoadmap({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final items = [
      (fa ? 'اتصال فقط خواندنی' : 'Read-only connection', connected),
      (fa ? 'Shadow Mode بدون سفارش' : 'Shadow Mode without orders', false),
      (fa ? 'تأیید دستی سفارش' : 'Manual order approval', false),
      (fa ? 'Canary با ریسک بسیار کم' : 'Tiny-risk live canary', false),
      (fa ? 'ترید خودکار محدود' : 'Restricted auto trading', false),
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'مراحل فعال‌سازی ایمن' : 'Safe activation stages',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                item.$2
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: item.$2
                    ? QuantaraColors.success
                    : Theme.of(context).colorScheme.outline,
              ),
              title: Text(item.$1),
            ),
          const SizedBox(height: 4),
          Text(
            fa
                ? 'برداشت، انتقال وجه، مارتینگل، Cross Margin و افزایش ریسک بعد از ضرر در طراحی Quantara ممنوع‌اند.'
                : 'Withdrawals, transfers, martingale, cross-margin automation, and increasing risk after losses are prohibited by design.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
