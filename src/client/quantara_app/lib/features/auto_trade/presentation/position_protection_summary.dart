import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../domain/auto_trade_models.dart';

final class PositionProtectionSummary extends StatelessWidget {
  const PositionProtectionSummary({
    required this.protection,
    required this.stale,
    required this.persian,
    super.key,
  });

  final AutoTradePositionProtection protection;
  final bool stale;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final status = protection.effectiveStatus(stale: stale);
    final presentation = _presentation(status);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: presentation.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: presentation.color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(presentation.icon, size: 18, color: presentation.color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  presentation.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: presentation.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _asOfLabel(),
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            protection.stopLoss == null
                ? (persian ? 'SL: تأیید نشده' : 'SL: not confirmed')
                : 'SL ${_number(protection.stopLoss!.price)} · Qty ${_quantity(protection.stopLoss!.quantity)}',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          if (protection.takeProfits.isEmpty)
            Text(
              persian ? 'TP: تأیید نشده' : 'TP: not confirmed',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (
                  var index = 0;
                  index < protection.takeProfits.length;
                  index++
                )
                  Text(
                    'TP${index + 1} ${_number(protection.takeProfits[index].price)} · Qty ${_quantity(protection.takeProfits[index].quantity)}',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          const SizedBox(height: 7),
          Text(
            '${persian ? 'جمع TP' : 'TP total'} ${_number(protection.totalTakeProfitQuantity)} · '
            '${persian ? 'باقی‌مانده' : 'Residual'} ${_number(protection.residualQuantity)}'
            '${protection.hasResidualDust ? (persian ? ' · Dust' : ' · Dust') : ''}',
            textDirection: TextDirection.ltr,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (protection.reason != null) ...[
            const SizedBox(height: 5),
            Text(
              protection.reason!,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }

  _ProtectionPresentation _presentation(AutoTradeProtectionStatus status) =>
      switch (status) {
        AutoTradeProtectionStatus.fullyProtected => _ProtectionPresentation(
          label: persian ? 'کاملاً محافظت‌شده' : 'Fully protected',
          color: QuantaraColors.success,
          icon: Icons.verified_user_rounded,
        ),
        AutoTradeProtectionStatus.missingStop => _ProtectionPresentation(
          label: persian ? 'حد ضرر ناقص/مفقود' : 'Missing stop',
          color: QuantaraColors.danger,
          icon: Icons.gpp_bad_rounded,
        ),
        AutoTradeProtectionStatus.incompleteLadder => _ProtectionPresentation(
          label: persian ? 'نردبان TP ناقص' : 'Incomplete ladder',
          color: QuantaraColors.warning,
          icon: Icons.stairs_outlined,
        ),
        AutoTradeProtectionStatus.unverified => _ProtectionPresentation(
          label: persian ? 'تأییدنشده' : 'Unverified',
          color: QuantaraColors.warning,
          icon: Icons.help_outline_rounded,
        ),
        AutoTradeProtectionStatus.stale => _ProtectionPresentation(
          label: persian ? 'قدیمی' : 'Stale',
          color: QuantaraColors.warning,
          icon: Icons.history_toggle_off_rounded,
        ),
      };

  String _asOfLabel() {
    final value = protection.asOf.toLocal();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return 'as of $hour:$minute:$second';
  }

  static String _quantity(double? value) =>
      value == null ? '—' : _number(value);

  static String _number(double value) {
    if (!value.isFinite) return '—';
    final fixed = value.toStringAsFixed(8);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

final class _ProtectionPresentation {
  const _ProtectionPresentation({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}
