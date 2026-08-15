import 'package:flutter/material.dart';

import '../data/opportunity_discovery_universe.dart';

class OpportunityDiscoveryCoverageBanner extends StatelessWidget {
  const OpportunityDiscoveryCoverageBanner({required this.coverage, super.key});

  final ValueListenable<OpportunityDiscoveryCoverageSnapshot>? coverage;

  @override
  Widget build(BuildContext context) {
    final listenable = coverage;
    if (listenable == null) return const SizedBox.shrink();
    return ValueListenableBuilder<OpportunityDiscoveryCoverageSnapshot>(
      valueListenable: listenable,
      builder: (context, snapshot, _) {
        final persian = Localizations.localeOf(context).languageCode != 'en';
        final scheme = Theme.of(context).colorScheme;
        final healthyCoverage = snapshot.eligibleSymbols >= 100;
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: healthyCoverage
                      ? scheme.primary.withValues(alpha: 0.28)
                      : scheme.error.withValues(alpha: 0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 19,
                      color: healthyCoverage ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _Metric(
                              label: persian ? 'پوشش' : 'Coverage',
                              value:
                                  '${snapshot.symbolsScanned}/${snapshot.eligibleSymbols}',
                            ),
                            _Metric(
                              label: persian ? 'درحال شکل‌گیری' : 'Forming',
                              value: '${snapshot.forming}',
                            ),
                            _Metric(
                              label: persian ? 'آماده' : 'Armed',
                              value: '${snapshot.armed}',
                            ),
                            _Metric(
                              label: persian ? 'تریگر' : 'Triggered',
                              value: '${snapshot.triggered}',
                            ),
                            _Metric(
                              label: persian ? 'از دست‌رفته' : 'Missed',
                              value: '${snapshot.missed}',
                            ),
                            _Metric(
                              label: persian ? 'ردشده' : 'Rejected',
                              value: '${snapshot.rejected}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
