import 'dart:async';

import '../domain/trader_agent_models.dart';

final class TraderAgentProbeSnapshot {
  const TraderAgentProbeSnapshot({
    required this.capital,
    required this.riskPercent,
    required this.selectedLeverage,
    required this.selectedSymbol,
    required this.selectedTimeframe,
    required this.liveTradingEnabled,
    required this.withdrawalEnabled,
    required this.autoTradeReadOnly,
    required this.unhandledErrorCount,
    required this.layoutOverflowCount,
    required this.endlessScrollDetected,
    required this.staleExecutablePlanDetected,
  });

  final double capital;
  final double riskPercent;
  final int selectedLeverage;
  final String selectedSymbol;
  final String selectedTimeframe;
  final bool liveTradingEnabled;
  final bool withdrawalEnabled;
  final bool autoTradeReadOnly;
  final int unhandledErrorCount;
  final int layoutOverflowCount;
  final bool endlessScrollDetected;
  final bool staleExecutablePlanDetected;
}

abstract interface class TraderAgentProbe {
  Future<void> reset({required int seed});

  Future<void> configure(TraderAgentPersona persona);

  Future<void> openFeature(TraderAgentFeature feature);

  Future<void> setCapital(double capital);

  Future<void> setRiskPercent(double riskPercent);

  Future<void> setLeverage(int leverage);

  Future<void> selectMarket({required String symbol, required String timeframe});

  Future<void> setNetworkProfile(TraderAgentNetworkProfile profile);

  Future<void> backgroundAndResume();

  Future<void> restart();

  Future<void> connectAutoTradeReadOnly();

  Future<void> rapidNavigate({required int iterations});

  Future<TraderAgentProbeSnapshot> snapshot();
}

final class TraderAgentFailure implements Exception {
  const TraderAgentFailure({
    required this.severity,
    required this.title,
    required this.details,
  });

  final TraderAgentSeverity severity;
  final String title;
  final String details;

  @override
  String toString() => '$title: $details';
}

final class TraderAgentLab {
  TraderAgentLab({
    this.stepTimeout = const Duration(seconds: 20),
    DateTime Function()? utcNow,
  }) : _utcNow = utcNow ?? DateTime.now;

  final Duration stepTimeout;
  final DateTime Function() _utcNow;

  Future<List<TraderAgentRunReport>> runAll({
    required TraderAgentProbe Function(TraderAgentPersona persona) probeFactory,
    int seed = 7302026,
  }) async {
    final reports = <TraderAgentRunReport>[];
    for (var index = 0; index < TraderAgentPersona.builtIn.length; index++) {
      final persona = TraderAgentPersona.builtIn[index];
      reports.add(
        await runPersona(
          persona: persona,
          probe: probeFactory(persona),
          seed: seed + index * 997,
        ),
      );
    }
    return List.unmodifiable(reports);
  }

  Future<TraderAgentRunReport> runPersona({
    required TraderAgentPersona persona,
    required TraderAgentProbe probe,
    required int seed,
  }) async {
    final startedAt = _utcNow().toUtc();
    final steps = <TraderAgentStepResult>[];
    final findings = <TraderAgentFinding>[];

    await _step(
      persona: persona,
      seed: seed,
      id: 'reset-and-configure',
      feature: TraderAgentFeature.onboarding,
      steps: steps,
      findings: findings,
      action: () async {
        await probe.reset(seed: seed);
        await probe.configure(persona);
      },
    );

    for (final feature in persona.focus) {
      await _step(
        persona: persona,
        seed: seed,
        id: 'open-${feature.name}',
        feature: feature,
        steps: steps,
        findings: findings,
        action: () => probe.openFeature(feature),
      );
    }

    await _step(
      persona: persona,
      seed: seed,
      id: 'capital-risk-propagation',
      feature: TraderAgentFeature.safety,
      steps: steps,
      findings: findings,
      action: () async {
        await probe.setCapital(persona.capital);
        await probe.setRiskPercent(persona.riskPercent);
        await probe.openFeature(TraderAgentFeature.setups);
        final state = await probe.snapshot();
        if ((state.capital - persona.capital).abs() > 0.0001) {
          throw TraderAgentFailure(
            severity: TraderAgentSeverity.p1,
            title: 'Sizing capital did not propagate',
            details:
                'Expected ${persona.capital}, received ${state.capital}. Setups may be sized from stale account capital.',
          );
        }
        if ((state.riskPercent - persona.riskPercent).abs() > 0.0001) {
          throw TraderAgentFailure(
            severity: TraderAgentSeverity.p1,
            title: 'Risk setting did not propagate',
            details:
                'Expected ${persona.riskPercent}%, received ${state.riskPercent}%.',
          );
        }
      },
    );

    await _step(
      persona: persona,
      seed: seed,
      id: 'market-switch-loop',
      feature: TraderAgentFeature.analysis,
      steps: steps,
      findings: findings,
      action: () async {
        for (final symbol in persona.symbols) {
          for (final timeframe in persona.timeframes) {
            await probe.selectMarket(symbol: symbol, timeframe: timeframe);
            await probe.openFeature(TraderAgentFeature.analysis);
          }
        }
      },
    );

    if (persona.focus.contains(TraderAgentFeature.accessibility)) {
      await _step(
        persona: persona,
        seed: seed,
        id: 'accessibility-navigation-stress',
        feature: TraderAgentFeature.accessibility,
        steps: steps,
        findings: findings,
        action: () => probe.rapidNavigate(iterations: 100),
      );
    }

    if (persona.focus.contains(TraderAgentFeature.background)) {
      await _step(
        persona: persona,
        seed: seed,
        id: 'background-network-cycle',
        feature: TraderAgentFeature.background,
        steps: steps,
        findings: findings,
        action: () async {
          await probe.setNetworkProfile(TraderAgentNetworkProfile.slow);
          await probe.backgroundAndResume();
          await probe.setNetworkProfile(TraderAgentNetworkProfile.intermittent);
          await probe.backgroundAndResume();
          await probe.setNetworkProfile(TraderAgentNetworkProfile.normal);
        },
      );
    }

    if (persona.focus.contains(TraderAgentFeature.autoTrade)) {
      await _step(
        persona: persona,
        seed: seed,
        id: 'autotrade-readonly-boundary',
        feature: TraderAgentFeature.autoTrade,
        steps: steps,
        findings: findings,
        action: () async {
          await probe.connectAutoTradeReadOnly();
          final state = await probe.snapshot();
          if (!state.autoTradeReadOnly) {
            throw const TraderAgentFailure(
              severity: TraderAgentSeverity.p1,
              title: 'Auto Trade did not enter read-only mode',
              details: 'Private account onboarding must fail closed.',
            );
          }
          if (state.liveTradingEnabled || state.withdrawalEnabled) {
            throw const TraderAgentFailure(
              severity: TraderAgentSeverity.p0,
              title: 'Unsafe exchange authority detected',
              details:
                  'Agent obtained live-trading or withdrawal authority before the staged execution gates.',
            );
          }
        },
      );
    }

    if (persona.focus.contains(TraderAgentFeature.persistence)) {
      await _step(
        persona: persona,
        seed: seed,
        id: 'restart-persistence',
        feature: TraderAgentFeature.persistence,
        steps: steps,
        findings: findings,
        action: () async {
          await probe.restart();
          final state = await probe.snapshot();
          if ((state.capital - persona.capital).abs() > 0.0001 ||
              (state.riskPercent - persona.riskPercent).abs() > 0.0001) {
            throw TraderAgentFailure(
              severity: TraderAgentSeverity.p1,
              title: 'Settings were lost after restart',
              details:
                  'Expected capital ${persona.capital} and risk ${persona.riskPercent}%, got ${state.capital} and ${state.riskPercent}%.',
            );
          }
        },
      );
    }

    await _step(
      persona: persona,
      seed: seed,
      id: 'final-health-gate',
      feature: TraderAgentFeature.safety,
      steps: steps,
      findings: findings,
      action: () async {
        final state = await probe.snapshot();
        if (state.unhandledErrorCount > 0) {
          throw TraderAgentFailure(
            severity: TraderAgentSeverity.p0,
            title: 'Unhandled application error detected',
            details: '${state.unhandledErrorCount} uncaught errors were recorded.',
          );
        }
        if (state.layoutOverflowCount > 0 || state.endlessScrollDetected) {
          throw TraderAgentFailure(
            severity: TraderAgentSeverity.p0,
            title: 'Layout or infinite-scroll regression detected',
            details:
                'Overflow count: ${state.layoutOverflowCount}; endless scroll: ${state.endlessScrollDetected}.',
          );
        }
        if (state.staleExecutablePlanDetected) {
          throw const TraderAgentFailure(
            severity: TraderAgentSeverity.p0,
            title: 'Stale executable plan detected',
            details:
                'A stale setup must never remain eligible for manual or automatic execution.',
          );
        }
        if (state.withdrawalEnabled) {
          throw const TraderAgentFailure(
            severity: TraderAgentSeverity.p0,
            title: 'Withdrawal capability detected',
            details: 'Quantara must not request or expose withdrawal authority.',
          );
        }
      },
    );

    return TraderAgentRunReport(
      persona: persona,
      seed: seed,
      startedAt: startedAt,
      finishedAt: _utcNow().toUtc(),
      steps: List.unmodifiable(steps),
      findings: List.unmodifiable(findings),
    );
  }

  Future<void> _step({
    required TraderAgentPersona persona,
    required int seed,
    required String id,
    required TraderAgentFeature feature,
    required List<TraderAgentStepResult> steps,
    required List<TraderAgentFinding> findings,
    required Future<void> Function() action,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      await action().timeout(stepTimeout);
      stopwatch.stop();
      steps.add(
        TraderAgentStepResult(
          id: id,
          feature: feature,
          status: TraderAgentStepStatus.passed,
          elapsed: stopwatch.elapsed,
        ),
      );
    } on TraderAgentFailure catch (error) {
      stopwatch.stop();
      steps.add(
        TraderAgentStepResult(
          id: id,
          feature: feature,
          status: TraderAgentStepStatus.failed,
          elapsed: stopwatch.elapsed,
          message: error.toString(),
        ),
      );
      findings.add(
        TraderAgentFinding(
          personaId: persona.id,
          stepId: id,
          feature: feature,
          severity: error.severity,
          title: error.title,
          details: error.details,
          seed: seed,
        ),
      );
    } on TimeoutException {
      stopwatch.stop();
      steps.add(
        TraderAgentStepResult(
          id: id,
          feature: feature,
          status: TraderAgentStepStatus.failed,
          elapsed: stopwatch.elapsed,
          message: 'Timed out after $stepTimeout.',
        ),
      );
      findings.add(
        TraderAgentFinding(
          personaId: persona.id,
          stepId: id,
          feature: feature,
          severity: TraderAgentSeverity.p0,
          title: 'Journey step timed out',
          details:
              'The step exceeded $stepTimeout and may indicate an infinite loader or navigation loop.',
          seed: seed,
        ),
      );
    } on Object catch (error) {
      stopwatch.stop();
      steps.add(
        TraderAgentStepResult(
          id: id,
          feature: feature,
          status: TraderAgentStepStatus.failed,
          elapsed: stopwatch.elapsed,
          message: error.toString(),
        ),
      );
      findings.add(
        TraderAgentFinding(
          personaId: persona.id,
          stepId: id,
          feature: feature,
          severity: TraderAgentSeverity.p0,
          title: 'Unexpected agent journey failure',
          details: error.toString(),
          seed: seed,
        ),
      );
    }
  }
}
