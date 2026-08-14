import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_diagnostic_evidence_adapter.dart';

void main() {
  test('adapts only explicitly registered diagnostic sections', () {
    final evidence = SupervisorDiagnosticEvidenceAdapter.fromDiagnosticBundle(
      bundleId: 'bundle-1',
      observedAtUtc: DateTime.utc(2026, 8, 14, 7),
      diagnosticBundle: <String, Object?>{
        'sections': <String, Object?>{
          'configuration': <String, Object?>{
            'leverage': 10,
            'riskPercent': 0.5,
          },
          'tradingJournal': <String, Object?>{'tradeCount': 4},
          'futureUnknownSection': <String, Object?>{'value': 'not-forwarded'},
        },
      },
    );

    expect(evidence, hasLength(2));
    expect(
      evidence.map((item) => item.evidenceId),
      containsAll(<String>{
        'diagnostic:bundle-1:configuration',
        'diagnostic:bundle-1:tradingJournal',
      }),
    );
    final serialized = evidence.map((item) => item.toJson().toString()).join();
    expect(serialized, isNot(contains('futureUnknownSection')));
    expect(serialized, isNot(contains('not-forwarded')));
  });

  test('sanitizes nested credential-bearing diagnostic values', () {
    final evidence = SupervisorDiagnosticEvidenceAdapter.fromDiagnosticBundle(
      bundleId: 'bundle-secret-check',
      observedAtUtc: DateTime.utc(2026, 8, 14, 7, 1),
      diagnosticBundle: <String, Object?>{
        'sections': <String, Object?>{
          'configuration': <String, Object?>{
            'symbols': <String>['SOLUSDT'],
            'nested': <String, Object?>{
              'apiKey': 'never-forward-this',
              'message': 'Authorization: Bearer also-never-forward-this',
            },
          },
        },
      },
    );

    final serialized = evidence.single.toJson().toString();
    expect(serialized, isNot(contains('never-forward-this')));
    expect(serialized, isNot(contains('also-never-forward-this')));
    expect(serialized, contains('REDACTED'));
  });

  test('canonicalizes section maps before serialization', () {
    final first = SupervisorDiagnosticEvidenceAdapter.fromDiagnosticBundle(
      bundleId: 'deterministic',
      observedAtUtc: DateTime.utc(2026, 8, 14, 7, 2),
      diagnosticBundle: <String, Object?>{
        'sections': <String, Object?>{
          'analysisRuntime': <String, Object?>{'z': 1, 'a': 2},
        },
      },
    );
    final second = SupervisorDiagnosticEvidenceAdapter.fromDiagnosticBundle(
      bundleId: 'deterministic',
      observedAtUtc: DateTime.utc(2026, 8, 14, 7, 2),
      diagnosticBundle: <String, Object?>{
        'sections': <String, Object?>{
          'analysisRuntime': <String, Object?>{'a': 2, 'z': 1},
        },
      },
    );

    expect(first.single.toJson(), second.single.toJson());
  });
}
