import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'portfolio_risk_models.dart';

enum CapitalGuardianBreakerReason {
  none,
  weeklyLossCap,
  drawdownHardStop,
  lossStreakCooldown,
  abnormalVolatility,
  reducedRiskAllowance,
}

enum CapitalGuardianDrawdownTier { normal, soft, hardStop, recovery }

@immutable
final class CapitalGuardianPolicy {
  const CapitalGuardianPolicy({
    this.weeklyLossLimitMultiplier = 3,
    this.softDrawdownFraction = 0.05,
    this.hardDrawdownFraction = 0.10,
    this.recoveryDrawdownFraction = 0.03,
    this.softRiskMultiplier = 0.5,
    this.recoveryRiskMultiplier = 0.25,
    this.consecutiveLossThreshold = 3,
    this.lossStreakCooldown = const Duration(hours: 4),
    this.volatilityCooldown = const Duration(hours: 1),
  }) : assert(weeklyLossLimitMultiplier > 0),
       assert(softDrawdownFraction >= 0),
       assert(hardDrawdownFraction > softDrawdownFraction),
       assert(recoveryDrawdownFraction >= 0),
       assert(recoveryDrawdownFraction < hardDrawdownFraction),
       assert(softRiskMultiplier >= 0 && softRiskMultiplier <= 1),
       assert(recoveryRiskMultiplier >= 0 && recoveryRiskMultiplier <= 1),
       assert(consecutiveLossThreshold > 0);

  final double weeklyLossLimitMultiplier;
  final double softDrawdownFraction;
  final double hardDrawdownFraction;
  final double recoveryDrawdownFraction;
  final double softRiskMultiplier;
  final double recoveryRiskMultiplier;
  final int consecutiveLossThreshold;
  final Duration lossStreakCooldown;
  final Duration volatilityCooldown;

  double weeklyLossLimit(double dailyRiskLimit) {
    if (!dailyRiskLimit.isFinite || dailyRiskLimit <= 0) {
      throw const FormatException('Daily risk limit is invalid.');
    }
    return dailyRiskLimit * weeklyLossLimitMultiplier;
  }

  CapitalGuardianDecision evaluate({
    required CapitalGuardianState state,
    required PortfolioRiskLedger ledger,
    required PortfolioEntryDecision baseDecision,
    required DateTime now,
  }) {
    final normalized = state.normalized(
      now: now,
      timezoneOffsetMinutes: ledger.tradingDay.timezoneOffsetMinutes,
    );
    final weeklyLimit = weeklyLossLimit(ledger.dailyRiskLimit);
    final weeklyRemaining = math
        .max(0, weeklyLimit - normalized.weeklyRealizedLoss)
        .toDouble();
    final multiplier = normalized.riskMultiplier(this);
    final maximumAllowedEntryRisk = math
        .min(weeklyRemaining, ledger.dailyRisk.limit * multiplier)
        .toDouble();

    CapitalGuardianDecision blocked(CapitalGuardianBreakerReason reason) =>
        CapitalGuardianDecision(
          allowed: false,
          reason: reason,
          drawdownTier: normalized.drawdownTier,
          riskMultiplier: multiplier,
          weeklyLossLimit: weeklyLimit,
          weeklyLossRemaining: weeklyRemaining,
          maximumAllowedEntryRisk: maximumAllowedEntryRisk,
        );

    if (normalized.weeklyRealizedLoss >= weeklyLimit - 1e-9) {
      return blocked(CapitalGuardianBreakerReason.weeklyLossCap);
    }
    if (normalized.drawdownTier == CapitalGuardianDrawdownTier.hardStop) {
      return blocked(CapitalGuardianBreakerReason.drawdownHardStop);
    }
    if (normalized.lossStreakCooldownUntilUtc != null &&
        now.toUtc().isBefore(normalized.lossStreakCooldownUntilUtc!)) {
      return blocked(CapitalGuardianBreakerReason.lossStreakCooldown);
    }
    if (normalized.volatilityBreakerUntilUtc != null &&
        now.toUtc().isBefore(normalized.volatilityBreakerUntilUtc!)) {
      return blocked(CapitalGuardianBreakerReason.abnormalVolatility);
    }
    if (baseDecision.allowed &&
        baseDecision.maximumLoss > maximumAllowedEntryRisk + 1e-9) {
      return blocked(CapitalGuardianBreakerReason.reducedRiskAllowance);
    }
    return CapitalGuardianDecision(
      allowed: true,
      reason: CapitalGuardianBreakerReason.none,
      drawdownTier: normalized.drawdownTier,
      riskMultiplier: multiplier,
      weeklyLossLimit: weeklyLimit,
      weeklyLossRemaining: weeklyRemaining,
      maximumAllowedEntryRisk: maximumAllowedEntryRisk,
    );
  }
}

@immutable
final class CapitalGuardianDecision {
  const CapitalGuardianDecision({
    required this.allowed,
    required this.reason,
    required this.drawdownTier,
    required this.riskMultiplier,
    required this.weeklyLossLimit,
    required this.weeklyLossRemaining,
    required this.maximumAllowedEntryRisk,
  });

  final bool allowed;
  final CapitalGuardianBreakerReason reason;
  final CapitalGuardianDrawdownTier drawdownTier;
  final double riskMultiplier;
  final double weeklyLossLimit;
  final double weeklyLossRemaining;
  final double maximumAllowedEntryRisk;
}

@immutable
final class CapitalGuardianState {
  const CapitalGuardianState({
    required this.schemaVersion,
    required this.revision,
    required this.weekId,
    required this.weekStartedAtUtc,
    required this.weeklyRealizedLoss,
    required this.consecutiveLosses,
    required this.drawdownFraction,
    required this.drawdownTier,
    required this.lossStreakCooldownUntilUtc,
    required this.volatilityBreakerUntilUtc,
  });

  factory CapitalGuardianState.initial({
    required DateTime now,
    required int timezoneOffsetMinutes,
  }) {
    final week = _TradingWeek.start(
      now: now,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
    return CapitalGuardianState(
      schemaVersion: 1,
      revision: 0,
      weekId: week.id,
      weekStartedAtUtc: week.startedAtUtc,
      weeklyRealizedLoss: 0,
      consecutiveLosses: 0,
      drawdownFraction: 0,
      drawdownTier: CapitalGuardianDrawdownTier.normal,
      lossStreakCooldownUntilUtc: null,
      volatilityBreakerUntilUtc: null,
    );
  }

  final int schemaVersion;
  final int revision;
  final String weekId;
  final DateTime weekStartedAtUtc;
  final double weeklyRealizedLoss;
  final int consecutiveLosses;
  final double drawdownFraction;
  final CapitalGuardianDrawdownTier drawdownTier;
  final DateTime? lossStreakCooldownUntilUtc;
  final DateTime? volatilityBreakerUntilUtc;

  double riskMultiplier(CapitalGuardianPolicy policy) => switch (drawdownTier) {
    CapitalGuardianDrawdownTier.normal => 1,
    CapitalGuardianDrawdownTier.soft => policy.softRiskMultiplier,
    CapitalGuardianDrawdownTier.hardStop => 0,
    CapitalGuardianDrawdownTier.recovery => policy.recoveryRiskMultiplier,
  };

  CapitalGuardianState normalized({
    required DateTime now,
    required int timezoneOffsetMinutes,
  }) {
    final timestamp = now.toUtc();
    final currentWeek = _TradingWeek.start(
      now: timestamp,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
    final weekChanged = currentWeek.id != weekId;
    final nextLossCooldown = _activeUntil(
      lossStreakCooldownUntilUtc,
      timestamp,
    );
    final nextVolatilityCooldown = _activeUntil(
      volatilityBreakerUntilUtc,
      timestamp,
    );
    if (!weekChanged &&
        nextLossCooldown == lossStreakCooldownUntilUtc &&
        nextVolatilityCooldown == volatilityBreakerUntilUtc) {
      return this;
    }
    return CapitalGuardianState(
      schemaVersion: schemaVersion,
      revision: revision + 1,
      weekId: currentWeek.id,
      weekStartedAtUtc: currentWeek.startedAtUtc,
      weeklyRealizedLoss: weekChanged ? 0 : weeklyRealizedLoss,
      consecutiveLosses: consecutiveLosses,
      drawdownFraction: drawdownFraction,
      drawdownTier: drawdownTier,
      lossStreakCooldownUntilUtc: nextLossCooldown,
      volatilityBreakerUntilUtc: nextVolatilityCooldown,
    );
  }

  CapitalGuardianState recordClose({
    required double exchangeConfirmedNetPnl,
    required DateTime now,
    required int timezoneOffsetMinutes,
    required CapitalGuardianPolicy policy,
  }) {
    if (!exchangeConfirmedNetPnl.isFinite) {
      throw const FormatException('Confirmed PnL is invalid.');
    }
    final base = normalized(
      now: now,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
    final loss = math.max(0, -exchangeConfirmedNetPnl).toDouble();
    final isLoss = loss > 1e-9;
    final nextStreak = isLoss ? base.consecutiveLosses + 1 : 0;
    final shouldCooldown =
        isLoss && nextStreak >= policy.consecutiveLossThreshold;
    final nextCooldown = shouldCooldown
        ? _laterOf(
            base.lossStreakCooldownUntilUtc,
            now.toUtc().add(policy.lossStreakCooldown),
          )
        : base.lossStreakCooldownUntilUtc;
    return CapitalGuardianState(
      schemaVersion: base.schemaVersion,
      revision: base.revision + 1,
      weekId: base.weekId,
      weekStartedAtUtc: base.weekStartedAtUtc,
      weeklyRealizedLoss: base.weeklyRealizedLoss + loss,
      consecutiveLosses: nextStreak,
      drawdownFraction: base.drawdownFraction,
      drawdownTier: base.drawdownTier,
      lossStreakCooldownUntilUtc: nextCooldown,
      volatilityBreakerUntilUtc: base.volatilityBreakerUntilUtc,
    );
  }

  CapitalGuardianState recordEnvironment({
    required double drawdownFraction,
    required bool abnormalVolatility,
    required DateTime now,
    required int timezoneOffsetMinutes,
    required CapitalGuardianPolicy policy,
  }) {
    if (!drawdownFraction.isFinite ||
        drawdownFraction < 0 ||
        drawdownFraction > 1) {
      throw const FormatException('Drawdown fraction is invalid.');
    }
    final base = normalized(
      now: now,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
    final nextTier = _drawdownTier(
      previous: base.drawdownTier,
      drawdownFraction: drawdownFraction,
      policy: policy,
    );
    final volatilityUntil = abnormalVolatility
        ? _laterOf(
            base.volatilityBreakerUntilUtc,
            now.toUtc().add(policy.volatilityCooldown),
          )
        : base.volatilityBreakerUntilUtc;
    return CapitalGuardianState(
      schemaVersion: base.schemaVersion,
      revision: base.revision + 1,
      weekId: base.weekId,
      weekStartedAtUtc: base.weekStartedAtUtc,
      weeklyRealizedLoss: base.weeklyRealizedLoss,
      consecutiveLosses: base.consecutiveLosses,
      drawdownFraction: drawdownFraction,
      drawdownTier: nextTier,
      lossStreakCooldownUntilUtc: base.lossStreakCooldownUntilUtc,
      volatilityBreakerUntilUtc: volatilityUntil,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'revision': revision,
    'weekId': weekId,
    'weekStartedAtUtc': weekStartedAtUtc.toUtc().toIso8601String(),
    'weeklyRealizedLoss': weeklyRealizedLoss,
    'consecutiveLosses': consecutiveLosses,
    'drawdownFraction': drawdownFraction,
    'drawdownTier': drawdownTier.name,
    'lossStreakCooldownUntilUtc': lossStreakCooldownUntilUtc
        ?.toUtc()
        .toIso8601String(),
    'volatilityBreakerUntilUtc': volatilityBreakerUntilUtc
        ?.toUtc()
        .toIso8601String(),
  };

  factory CapitalGuardianState.fromJson(Map<String, Object?> json) {
    final weekStartedAtUtc = DateTime.tryParse(
      json['weekStartedAtUtc']?.toString() ?? '',
    )?.toUtc();
    final lossCooldown = _optionalDate(json['lossStreakCooldownUntilUtc']);
    final volatilityCooldown = _optionalDate(json['volatilityBreakerUntilUtc']);
    final state = CapitalGuardianState(
      schemaVersion: _int(json['schemaVersion']),
      revision: _int(json['revision']),
      weekId: json['weekId']?.toString().trim() ?? '',
      weekStartedAtUtc:
          weekStartedAtUtc ??
          (throw const FormatException('Capital Guardian week is invalid.')),
      weeklyRealizedLoss: _double(json['weeklyRealizedLoss']),
      consecutiveLosses: _int(json['consecutiveLosses']),
      drawdownFraction: _double(json['drawdownFraction']),
      drawdownTier: CapitalGuardianDrawdownTier.values.firstWhere(
        (item) => item.name == json['drawdownTier'],
        orElse: () =>
            throw const FormatException('Capital Guardian tier is invalid.'),
      ),
      lossStreakCooldownUntilUtc: lossCooldown,
      volatilityBreakerUntilUtc: volatilityCooldown,
    );
    if (state.schemaVersion != 1 ||
        state.revision < 0 ||
        state.weekId.isEmpty ||
        !state.weeklyRealizedLoss.isFinite ||
        state.weeklyRealizedLoss < 0 ||
        state.consecutiveLosses < 0 ||
        !state.drawdownFraction.isFinite ||
        state.drawdownFraction < 0 ||
        state.drawdownFraction > 1) {
      throw const FormatException('Capital Guardian state failed validation.');
    }
    return state;
  }
}

CapitalGuardianDrawdownTier _drawdownTier({
  required CapitalGuardianDrawdownTier previous,
  required double drawdownFraction,
  required CapitalGuardianPolicy policy,
}) {
  if (drawdownFraction >= policy.hardDrawdownFraction) {
    return CapitalGuardianDrawdownTier.hardStop;
  }
  if ((previous == CapitalGuardianDrawdownTier.hardStop ||
          previous == CapitalGuardianDrawdownTier.recovery) &&
      drawdownFraction > policy.recoveryDrawdownFraction) {
    return CapitalGuardianDrawdownTier.recovery;
  }
  if (drawdownFraction >= policy.softDrawdownFraction) {
    return CapitalGuardianDrawdownTier.soft;
  }
  return CapitalGuardianDrawdownTier.normal;
}

@immutable
final class _TradingWeek {
  const _TradingWeek({required this.id, required this.startedAtUtc});

  factory _TradingWeek.start({
    required DateTime now,
    required int timezoneOffsetMinutes,
  }) {
    if (timezoneOffsetMinutes < -14 * 60 || timezoneOffsetMinutes > 14 * 60) {
      throw const FormatException('Trading-week timezone offset is invalid.');
    }
    final local = now.toUtc().add(Duration(minutes: timezoneOffsetMinutes));
    final localMidnight = DateTime.utc(local.year, local.month, local.day);
    final mondayLocal = localMidnight.subtract(
      Duration(days: local.weekday - DateTime.monday),
    );
    final mondayUtc = mondayLocal.subtract(
      Duration(minutes: timezoneOffsetMinutes),
    );
    final date =
        '${mondayLocal.year.toString().padLeft(4, '0')}-'
        '${mondayLocal.month.toString().padLeft(2, '0')}-'
        '${mondayLocal.day.toString().padLeft(2, '0')}';
    return _TradingWeek(id: date, startedAtUtc: mondayUtc);
  }

  final String id;
  final DateTime startedAtUtc;
}

DateTime? _activeUntil(DateTime? value, DateTime now) =>
    value != null && now.isBefore(value) ? value : null;

DateTime _laterOf(DateTime? current, DateTime candidate) =>
    current != null && current.isAfter(candidate) ? current : candidate;

DateTime? _optionalDate(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc() ??
      (throw const FormatException('Capital Guardian timestamp is invalid.'));
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? -1;

double _double(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? double.nan;
