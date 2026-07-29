from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'src' / 'client' / 'quantara_app'


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        raise SystemExit(f'patch target not found in {path}: {marker}')
    path.write_text(text.replace(old, new, 1))


priority = ROOT / 'lib/features/owner_alpha/data/signal_timeframe_priority.dart'
priority.write_text(r'''import '../domain/owner_alpha_models.dart';

enum SignalTimeframePriorityKind { primary, secondary, conflict }

abstract final class SignalTimeframePriorityResolver {
  static Map<String, SignalTimeframePriorityKind> resolve(
    Iterable<SignalJournalEntry> entries, {
    required DateTime now,
  }) {
    final active = entries.where((entry) {
      if (entry.closed || entry.hasTerminalOutcome) return false;
      if (entry.outcome == SignalOutcome.pendingEntry &&
          !now.toUtc().isBefore(entry.validUntil)) {
        return false;
      }
      return true;
    });
    final grouped = <String, List<SignalJournalEntry>>{};
    for (final entry in active) {
      grouped.putIfAbsent(entry.symbol, () => []).add(entry);
    }

    final result = <String, SignalTimeframePriorityKind>{};
    for (final group in grouped.values) {
      final directions = group.map((entry) => entry.direction).toSet();
      if (directions.length > 1) {
        for (final entry in group) {
          result[entry.setupId] = SignalTimeframePriorityKind.conflict;
        }
        continue;
      }

      final primary = _pickPrimary(group);
      for (final entry in group) {
        result[entry.setupId] = identical(entry, primary)
            ? SignalTimeframePriorityKind.primary
            : SignalTimeframePriorityKind.secondary;
      }
    }
    return Map.unmodifiable(result);
  }

  static SignalJournalEntry _pickPrimary(List<SignalJournalEntry> group) {
    final hasFourHour = group.any((entry) => entry.timeframe == '4h');
    final preferredTimeframe = hasFourHour &&
            group.any((entry) => entry.timeframe == '1h')
        ? '1h'
        : group.any((entry) => entry.timeframe == '4h')
            ? '4h'
            : group.any((entry) => entry.timeframe == '1h')
                ? '1h'
                : group.any((entry) => entry.timeframe == '15m')
                    ? '15m'
                    : group.any((entry) => entry.timeframe == '1D')
                        ? '1D'
                        : group.first.timeframe;
    final candidates = group
        .where((entry) => entry.timeframe == preferredTimeframe)
        .toList(growable: false)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return candidates.first;
  }
}
''')

page = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace_once(
    page,
    "import '../application/owner_alpha_controller.dart';\n",
    "import '../application/owner_alpha_controller.dart';\nimport '../data/signal_timeframe_priority.dart';\n",
    "import '../data/signal_timeframe_priority.dart';",
)

signals = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_signals.dart'
replace_once(
    signals,
    '''    final filtered = all
        .where((entry) {''',
    '''    final priorityBySetupId = SignalTimeframePriorityResolver.resolve(
      all,
      now: now,
    );
    final filtered = all
        .where((entry) {''',
    'final priorityBySetupId = SignalTimeframePriorityResolver.resolve(',
)
replace_once(
    signals,
    '''              entry: filtered[index],
              taken: controller.isTaken(filtered[index].setupId),''',
    '''              entry: filtered[index],
              priority: priorityBySetupId[filtered[index].setupId],
              taken: controller.isTaken(filtered[index].setupId),''',
    'priority: priorityBySetupId[filtered[index].setupId],',
)
replace_once(
    signals,
    '''    required this.entry,
    required this.taken,''',
    '''    required this.entry,
    required this.priority,
    required this.taken,''',
    'required this.priority,',
)
replace_once(
    signals,
    '''  final SignalJournalEntry entry;
  final bool taken;''',
    '''  final SignalJournalEntry entry;
  final SignalTimeframePriorityKind? priority;
  final bool taken;''',
    'final SignalTimeframePriorityKind? priority;',
)
replace_once(
    signals,
    '''                StatusPill(
                  label: _t(
                    context,
                    '${entry.selectedLeverage}x انتخابی',
                    '${entry.selectedLeverage}x selected',
                  ),
                  color: QuantaraColors.violet,
                ),
              ],''',
    '''                StatusPill(
                  label: _t(
                    context,
                    '${entry.selectedLeverage}x انتخابی',
                    '${entry.selectedLeverage}x selected',
                  ),
                  color: QuantaraColors.violet,
                ),
                if (priority == SignalTimeframePriorityKind.primary)
                  StatusPill(
                    label: _t(context, 'گزینه اصلی', 'Primary setup'),
                    color: QuantaraColors.cyan,
                    icon: Icons.stars_rounded,
                  ),
                if (priority == SignalTimeframePriorityKind.conflict)
                  StatusPill(
                    label: _t(
                      context,
                      'تعارض تایم‌فریم',
                      'Timeframe conflict',
                    ),
                    color: QuantaraColors.danger,
                    icon: Icons.sync_problem_rounded,
                  ),
              ],''',
    "label: _t(context, 'گزینه اصلی', 'Primary setup'),",
)
replace_once(
    signals,
    '''            Text(entry.summary),
            const SizedBox(height: 12),''',
    '''            Text(entry.summary),
            if (priority == SignalTimeframePriorityKind.primary) ...[
              const SizedBox(height: 8),
              Text(
                _t(
                  context,
                  'برای این نماد، این تایم‌فریم گزینه اجرای اصلی است؛ تایم بالاتر جهت و تایم پایین‌تر فقط ماشه ورود است.',
                  'This is the primary execution timeframe for the symbol; higher timeframes define bias and lower timeframes only refine the trigger.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: QuantaraColors.cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (priority == SignalTimeframePriorityKind.conflict) ...[
              const SizedBox(height: 8),
              Text(
                _t(
                  context,
                  'جهت ستاپ‌های این نماد بین تایم‌فریم‌ها متناقض است؛ هم‌زمان هر دو جهت را نگیر و تا هم‌جهتی صبر کن.',
                  'This symbol has conflicting setup directions across timeframes. Do not take both directions; wait for alignment.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: QuantaraColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),''',
    'This is the primary execution timeframe for the symbol;',
)

(ROOT / 'test/signal_timeframe_priority_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/signal_timeframe_priority.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 7, 30, 1);

  test('prefers 1h execution when 4h bias agrees', () {
    final fourHour = _entry('four', '4h', TradeDirection.long, now);
    final oneHour = _entry('one', '1h', TradeDirection.long, now);
    final result = SignalTimeframePriorityResolver.resolve(
      [fourHour, oneHour],
      now: now,
    );

    expect(result['one'], SignalTimeframePriorityKind.primary);
    expect(result['four'], SignalTimeframePriorityKind.secondary);
  });

  test('marks all live setups conflicting when directions disagree', () {
    final fourHour = _entry('four', '4h', TradeDirection.long, now);
    final fifteen = _entry('fifteen', '15m', TradeDirection.short, now);
    final result = SignalTimeframePriorityResolver.resolve(
      [fourHour, fifteen],
      now: now,
    );

    expect(result['four'], SignalTimeframePriorityKind.conflict);
    expect(result['fifteen'], SignalTimeframePriorityKind.conflict);
  });

  test('uses the only live timeframe as primary', () {
    final fourHour = _entry('four', '4h', TradeDirection.long, now);
    final result = SignalTimeframePriorityResolver.resolve(
      [fourHour],
      now: now,
    );

    expect(result['four'], SignalTimeframePriorityKind.primary);
  });
}

SignalJournalEntry _entry(
  String id,
  String timeframe,
  TradeDirection direction,
  DateTime now,
) => SignalJournalEntry(
  setupId: id,
  symbol: 'BTCUSDT',
  timeframe: timeframe,
  direction: direction,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test',
  createdAt: now.subtract(const Duration(minutes: 5)),
  validUntil: now.add(const Duration(hours: 12)),
  entryLower: 100,
  entryUpper: 101,
  stopLoss: 95,
  targets: const [105, 110, 115],
  maximumLoss: 100,
  positionSize: 10,
  notionalValue: 1000,
  estimatedRoundTripCosts: 2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
);
''')
