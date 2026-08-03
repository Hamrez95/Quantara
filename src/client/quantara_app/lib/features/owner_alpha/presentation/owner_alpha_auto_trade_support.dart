part of 'owner_alpha_page.dart';

String _pnlMetricText(TradingPnlMetric metric) {
  final value = metric.value;
  if (value == null) return '—';
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(4)} ${metric.currency}';
}

Color? _pnlMetricColor(TradingPnlMetric metric) {
  final value = metric.value;
  if (value == null) return null;
  return value >= 0 ? QuantaraColors.success : QuantaraColors.danger;
}

class _DisconnectedAccountCard extends StatelessWidget {
  const _DisconnectedAccountCard({required this.busy, required this.onConnect});

  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fa
                    ? 'حساب Bitunix متصل نیست'
                    : 'Bitunix account is disconnected',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                fa
                    ? 'برای دریافت موجودی و فعال‌سازی Canary محلی، کلید API بدون دسترسی برداشت را وارد کن.'
                    : 'Enter an API key without withdrawal permission to load the account and enable the local canary.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SafetyChip(
                    icon: Icons.visibility_outlined,
                    label: fa ? 'مشاهده و ترید فقط' : 'Read & trade only',
                  ),
                  _SafetyChip(
                    icon: Icons.block_rounded,
                    label: fa ? 'برداشت ممنوع' : 'No withdrawals',
                  ),
                  _SafetyChip(
                    icon: Icons.lock_outline_rounded,
                    label: fa ? 'ذخیره امن دستگاه' : 'Device secure storage',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy ? null : onConnect,
                icon: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: busy
                      ? const SizedBox.square(
                          key: ValueKey('busy'),
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.add_link_rounded,
                          key: ValueKey('connect'),
                        ),
                ),
                label: Text(fa ? 'اتصال حساب' : 'Connect account'),
              ),
            ],
          );
          final illustration = _SecureConnectionIllustration(
            animate: !reduceMotion && !busy,
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.center, child: illustration),
                const SizedBox(height: 18),
                copy,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 28),
              illustration,
            ],
          );
        },
      ),
    );
  }
}

class _SecureConnectionIllustration extends StatelessWidget {
  const _SecureConnectionIllustration({required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: animate ? 1 : 0.5),
      duration: animate ? const Duration(milliseconds: 1800) : Duration.zero,
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        final lift = math.sin(value * math.pi * 2) * 5;
        return Transform.translate(
          offset: Offset(0, lift),
          child: Semantics(
            label: 'Secure exchange connection illustration',
            image: true,
            child: SizedBox(
              width: 180,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 148,
                    height: 116,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          QuantaraColors.violet.withValues(alpha: 0.22),
                          QuantaraColors.cyan.withValues(alpha: 0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 42,
                    child: _ConnectionNode(
                      icon: Icons.phone_android_rounded,
                      color: QuantaraColors.violet,
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 42,
                    child: _ConnectionNode(
                      icon: Icons.candlestick_chart_rounded,
                      color: QuantaraColors.cyan,
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.92 + (value * 0.08),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 20,
                            color: QuantaraColors.success.withValues(
                              alpha: 0.24,
                            ),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: QuantaraColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionNode extends StatelessWidget {
  const _ConnectionNode({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _SafetyChip extends StatelessWidget {
  const _SafetyChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: QuantaraColors.cyan),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _AccountOverviewCard extends StatelessWidget {
  const _AccountOverviewCard({
    required this.snapshot,
    required this.reconciliation,
    required this.maskedApiKey,
    required this.onRefresh,
    required this.onDisconnect,
  });

  final AutoTradeAccountSnapshot snapshot;
  final PrivateAccountReconciliationState reconciliation;
  final String maskedApiKey;
  final Future<bool> Function()? onRefresh;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final pnl = snapshot.authoritativePnl;
    final pnlColor = _pnlMetricColor(pnl.accountUnrealized);
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
                value: _pnlMetricText(pnl.accountUnrealized),
                valueColor: pnlColor,
              ),
              MetricTile(
                label: fa ? 'سود تحقق‌یافته ناخالص' : 'Realized gross',
                value: _pnlMetricText(pnl.accountRealizedGross),
                valueColor: _pnlMetricColor(pnl.accountRealizedGross),
              ),
              MetricTile(
                label: fa ? 'کارمزد' : 'Fees',
                value: _pnlMetricText(pnl.accountFees),
              ),
              MetricTile(
                label: fa ? 'فاندینگ' : 'Funding',
                value: _pnlMetricText(pnl.accountFunding),
                valueColor: _pnlMetricColor(pnl.accountFunding),
              ),
              MetricTile(
                label: fa ? 'سود/زیان خالص تحقق‌یافته' : 'Net realized',
                value: _pnlMetricText(pnl.accountNetRealized),
                valueColor: _pnlMetricColor(pnl.accountNetRealized),
              ),
              MetricTile(
                label: fa ? 'پوزیشن باز' : 'Open positions',
                value: snapshot.positions.length.toString(),
              ),
              MetricTile(
                label: fa ? 'کل سفارش‌های Pending' : 'Pending total',
                value: snapshot.totalPendingOrderCount.toString(),
              ),
              MetricTile(
                label: fa ? 'فید سفارش عادی' : 'Regular feed',
                value: snapshot.orders.length.toString(),
              ),
              MetricTile(
                label: fa ? 'سفارش حفاظتی' : 'Protection orders',
                value: snapshot.protectionOrders.length.toString(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${fa ? 'آخرین همگام‌سازی' : 'Last sync'}: ${snapshot.syncedAt.toLocal()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            '${fa ? 'زمان حسابداری صرافی' : 'Exchange accounting as of'}: ${pnl.asOf.toLocal()} · ${pnl.isVerified ? (fa ? 'تأییدشده' : 'verified') : (fa ? 'نیازمند بررسی' : 'unverified')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (pnl.warning != null)
            Text(
              pnl.warning!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: QuantaraColors.warning),
            ),
          Text(
            '${fa ? 'چرخه تطبیق' : 'Reconciliation cycle'}: ${reconciliation.cycleId ?? '—'}',
            textDirection: TextDirection.ltr,
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
                  fa ? 'واچ‌لیست قابل انتخاب' : 'Selectable watchlist',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const StatusPill(
                label: 'ALLOW-LIST',
                color: QuantaraColors.cyan,
                icon: Icons.rule_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fa
                ? 'وجود نماد در تحلیل به‌تنهایی مجوز معامله نیست؛ فقط نمادهای انتخاب‌شده در کارت Start می‌توانند وارد Canary شوند.'
                : 'Analysis membership alone never grants trading authority; only symbols explicitly selected in the Start card may enter the canary.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final symbol in symbols)
                InputChip(
                  label: Text(symbol, textDirection: TextDirection.ltr),
                  avatar: const Icon(Icons.visibility_outlined, size: 17),
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
  const _OpenPositionsCard({
    required this.snapshot,
    required this.reconciliation,
  });

  final AutoTradeAccountSnapshot snapshot;
  final PrivateAccountReconciliationState reconciliation;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final stale =
        reconciliation.health == PrivateAccountReconciliationHealth.stale;
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
            _CompactEmptyState(
              icon: Icons.shield_moon_outlined,
              title: fa ? 'پوزیشن بازی وجود ندارد' : 'No open positions',
              message: fa
                  ? 'بازار زیر نظر است؛ فقط ستاپ معتبر و داخل محدوده ورود اجازه اجرا می‌گیرد.'
                  : 'The market is monitored; only a valid setup inside its entry zone can execute.',
            )
          else
            for (final position in snapshot.positions) ...[
              Builder(
                builder: (context) {
                  final positionPnl = snapshot.authoritativePnl.forPositionId(
                    position.positionId,
                  );
                  final unrealized = positionPnl?.unrealized;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text(
                            position.symbol.isEmpty
                                ? '?'
                                : position.symbol.substring(0, 1),
                          ),
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
                          unrealized == null ? '—' : _pnlMetricText(unrealized),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: unrealized == null
                                ? null
                                : _pnlMetricColor(unrealized),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (positionPnl != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 10,
                            children: [
                              MetricTile(
                                label: fa ? 'تحقق‌یافته' : 'Realized',
                                value: _pnlMetricText(
                                  positionPnl.realizedGross,
                                ),
                                valueColor: _pnlMetricColor(
                                  positionPnl.realizedGross,
                                ),
                              ),
                              MetricTile(
                                label: fa ? 'کارمزد' : 'Fees',
                                value: _pnlMetricText(positionPnl.fees),
                              ),
                              MetricTile(
                                label: fa ? 'فاندینگ' : 'Funding',
                                value: _pnlMetricText(positionPnl.funding),
                              ),
                              MetricTile(
                                label: fa ? 'خالص' : 'Net',
                                value: _pnlMetricText(positionPnl.netRealized),
                                valueColor: _pnlMetricColor(
                                  positionPnl.netRealized,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              PositionProtectionSummary(
                protection: snapshot.protectionForPosition(position),
                stale: stale,
                persian: fa,
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
    final regularOrders = snapshot.regularOrdersNotRepresentedByProtection;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'سفارش‌های Pending Bitunix' : 'Pending Bitunix orders',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            fa
                ? '${snapshot.orders.length} ردیف عادی + ${snapshot.protectionOrders.length} ردیف حفاظتی · ${snapshot.totalPendingOrderCount} سفارش یکتا'
                : '${snapshot.orders.length} regular feed rows + ${snapshot.protectionOrders.length} protection rows · ${snapshot.totalPendingOrderCount} unique orders',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (snapshot.totalPendingOrderCount == 0)
            _CompactEmptyState(
              icon: Icons.receipt_long_outlined,
              title: fa ? 'سفارش Pending وجود ندارد' : 'No pending orders',
              message: fa
                  ? 'سفارش‌های عادی و Position TP/SL با دو مسیر مستقل خوانده می‌شوند.'
                  : 'Regular orders and Position TP/SL are read through independent exchange paths.',
            )
          else ...[
            for (final order in regularOrders) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  '${order.symbol} · ${order.side} · ${order.orderType}',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(
                  'Regular · Qty ${order.filledQuantity}/${order.quantity} · ${order.leverage}x · ${order.marginMode}',
                  textDirection: TextDirection.ltr,
                ),
              ),
              const Divider(height: 1),
            ],
            for (final order in snapshot.protectionOrders) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: Text(
                  '${order.symbol} · Position TP/SL',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(
                  _protectionOrderDescription(order),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ],
      ),
    );
  }

  static String _protectionOrderDescription(AutoTradeProtectionOrder order) {
    final values = <String>[];
    if (order.stopLossPrice != null) {
      values.add(
        'SL ${order.stopLossPrice} · Qty ${order.stopLossQuantity ?? '—'}',
      );
    }
    if (order.takeProfitPrice != null) {
      values.add(
        'TP ${order.takeProfitPrice} · Qty ${order.takeProfitQuantity ?? '—'}',
      );
    }
    values.add('ID ${order.exchangeId.isEmpty ? '—' : order.exchangeId}');
    return values.join(' · ');
  }
}

class _CompactEmptyState extends StatelessWidget {
  const _CompactEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            QuantaraColors.violet.withValues(alpha: 0.08),
            QuantaraColors.cyan.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: QuantaraColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: QuantaraColors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
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
      (fa ? 'اتصال حساب' : 'Account connection', connected),
      (fa ? 'Canary محلی یک‌پوزیشن' : 'One-position local canary', connected),
      (fa ? 'گزارش و مدار ایمنی' : 'Audit and circuit breaker', connected),
      (fa ? 'تست فیزیکی با موجودی کم' : 'Small-balance physical canary', false),
      (fa ? 'اجرای سروری همیشه‌روشن' : 'Always-on server execution', false),
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
                ? 'برداشت، انتقال وجه، مارتینگل، Cross Margin، میانگین کم‌کردن و افزایش ریسک بعد از ضرر در Quantara ممنوع‌اند.'
                : 'Withdrawals, transfers, martingale, cross-margin automation, averaging down, and increasing risk after losses are prohibited.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
