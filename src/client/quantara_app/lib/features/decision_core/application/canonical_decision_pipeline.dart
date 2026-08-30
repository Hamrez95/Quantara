import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/canonical_decision_models.dart';

abstract final class CanonicalDecisionPipeline {
  static const version = 'canonical-decision/1.0';

  static CanonicalDecisionRecord evaluate(CanonicalDecisionInput input) {
    final plan = input.plan;
    final provenance = input.provenance;
    final rules = input.instrumentRules;
    final economics = input.economics;
    final decisionKey = _decisionKey(plan, provenance.strategyConfigId);
    final reasons = <String>[
      ...plan.reasonCodes,
      'pipeline:$version',
      'strategy:${plan.strategy}@${plan.strategyVersion}',
      'config:${provenance.strategyConfigId}',
      'rules:${rules.exchangeRulesKnown ? 'known' : 'synthetic'}',
      'economics:${economics.version}',
    ];

    CanonicalDecisionRecord rejected(
      CanonicalDecisionRejection rejection, {
      double referenceEntry = 0,
      double normalizedEntry = 0,
      double normalizedStop = 0,
      double quantity = 0,
      double notional = 0,
      int leverage = 0,
      double requiredMargin = 0,
      double bufferedMarginRequirement = 0,
      double riskBudget = 0,
      double plannedRisk = 0,
      double riskPerUnit = 0,
      double estimatedRoundTripCosts = 0,
      double executionCostToRiskPercent = 0,
      double portfolioRiskAfter = 0,
      double symbolRiskAfter = 0,
    }) => _record(
      disposition: CanonicalDecisionDisposition.rejected,
      rejection: rejection,
      decisionKey: decisionKey,
      plan: plan,
      provenance: provenance,
      rules: rules,
      economics: economics,
      referenceEntry: referenceEntry,
      normalizedEntry: normalizedEntry,
      normalizedStop: normalizedStop,
      quantity: quantity,
      notional: notional,
      leverage: leverage,
      requiredMargin: requiredMargin,
      bufferedMarginRequirement: bufferedMarginRequirement,
      riskBudget: riskBudget,
      plannedRisk: plannedRisk,
      riskPerUnit: riskPerUnit,
      estimatedRoundTripCosts: estimatedRoundTripCosts,
      executionCostToRiskPercent: executionCostToRiskPercent,
      portfolioRiskAfter: portfolioRiskAfter,
      symbolRiskAfter: symbolRiskAfter,
      reasonCodes: [...reasons, 'reject:${rejection.name}'],
    );

    if (!plan.isActionable) {
      return rejected(CanonicalDecisionRejection.nonActionable);
    }
    if (provenance.eventTimeUtc.isBefore(plan.createdAtUtc)) {
      return rejected(CanonicalDecisionRejection.evidenceNotClosed);
    }
    if (!provenance.eventTimeUtc.isBefore(plan.validUntilUtc)) {
      return rejected(CanonicalDecisionRejection.expired);
    }
    if (plan.entryLower == null ||
        plan.entryUpper == null ||
        plan.stopLoss == null ||
        plan.entryLower! <= 0 ||
        plan.entryUpper! < plan.entryLower! ||
        plan.stopLoss! <= 0 ||
        plan.targets.isEmpty ||
        plan.targets.any((value) => !value.isFinite || value <= 0) ||
        plan.maximumSafeLeverage < 1) {
      return rejected(CanonicalDecisionRejection.incompletePlan);
    }
    if (input.alreadyExecuted) {
      return rejected(CanonicalDecisionRejection.alreadyExecuted);
    }
    if (input.symbolOccupied) {
      return rejected(CanonicalDecisionRejection.symbolOccupied);
    }
    if (!input.marketPrice.isFinite || input.marketPrice <= 0) {
      return rejected(CanonicalDecisionRejection.invalidMarketPrice);
    }
    if (!rules.isValid ||
        !economics.isValid ||
        !input.portfolio.isValid ||
        !input.equity.isFinite ||
        input.equity <= 0 ||
        !input.availableMargin.isFinite ||
        input.availableMargin < 0 ||
        !input.riskPercent.isFinite ||
        input.riskPercent <= 0 ||
        input.riskPercent > 2 ||
        input.requestedLeverage < 1) {
      return rejected(CanonicalDecisionRejection.invalidInstrumentRules);
    }
    if (!rules.open) {
      return rejected(CanonicalDecisionRejection.marketClosed);
    }
    if (!rules.apiSupported) {
      return rejected(CanonicalDecisionRejection.apiUnsupported);
    }

    final lower = math.min(plan.entryLower!, plan.entryUpper!);
    final upper = math.max(plan.entryLower!, plan.entryUpper!);
    if (input.marketPrice < lower || input.marketPrice > upper) {
      return rejected(
        CanonicalDecisionRejection.markOutsideEntry,
        referenceEntry: input.marketPrice,
      );
    }

    final normalizedEntry = _roundPrice(
      input.marketPrice,
      rules.pricePrecision,
    );
    final normalizedStop = _roundPrice(plan.stopLoss!, rules.pricePrecision);
    final stopOnCorrectSide = switch (plan.direction) {
      TradeDirection.long => normalizedStop < normalizedEntry,
      TradeDirection.short => normalizedStop > normalizedEntry,
      TradeDirection.wait => false,
    };
    if (!stopOnCorrectSide) {
      return rejected(
        CanonicalDecisionRejection.wrongSideStop,
        referenceEntry: input.marketPrice,
        normalizedEntry: normalizedEntry,
        normalizedStop: normalizedStop,
      );
    }

    final maximumAllowedLeverage = math.min(
      rules.maximumLeverage,
      plan.maximumSafeLeverage,
    );
    if (maximumAllowedLeverage < rules.minimumLeverage) {
      return rejected(
        CanonicalDecisionRejection.invalidInstrumentRules,
        referenceEntry: input.marketPrice,
        normalizedEntry: normalizedEntry,
        normalizedStop: normalizedStop,
      );
    }
    final leverage = input.requestedLeverage
        .clamp(rules.minimumLeverage, maximumAllowedLeverage)
        .toInt();
    final riskBudget = input.equity * input.riskPercent / 100;
    final estimatedCostPerUnit =
        normalizedEntry * economics.estimatedRoundTripRate;
    final riskPerUnit =
        (normalizedEntry - normalizedStop).abs() + estimatedCostPerUnit;
    if (!riskPerUnit.isFinite || riskPerUnit <= 0 || riskBudget <= 0) {
      return rejected(
        CanonicalDecisionRejection.incompletePlan,
        referenceEntry: input.marketPrice,
        normalizedEntry: normalizedEntry,
        normalizedStop: normalizedStop,
        leverage: leverage,
        riskBudget: riskBudget,
      );
    }

    final quantity = _roundQuantityDown(
      riskBudget / riskPerUnit,
      rules.quantityPrecision,
    );
    final notional = quantity * normalizedEntry;
    final plannedRisk = quantity * riskPerUnit;
    final estimatedRoundTripCosts = quantity * estimatedCostPerUnit;
    final executionCostToRiskPercent = riskBudget <= 0
        ? double.infinity
        : estimatedRoundTripCosts / riskBudget * 100;
    final requiredMargin = leverage <= 0 ? 0.0 : notional / leverage;
    final bufferedMarginRequirement =
        requiredMargin * economics.marginSafetyBufferMultiplier;
    final portfolioRiskAfter = input.portfolio.openRisk + plannedRisk;
    final symbolRiskAfter = input.portfolio.symbolRisk + plannedRisk;

    CanonicalDecisionRecord rejectSized(CanonicalDecisionRejection reason) =>
        rejected(
          reason,
          referenceEntry: input.marketPrice,
          normalizedEntry: normalizedEntry,
          normalizedStop: normalizedStop,
          quantity: quantity,
          notional: notional,
          leverage: leverage,
          requiredMargin: requiredMargin,
          bufferedMarginRequirement: bufferedMarginRequirement,
          riskBudget: riskBudget,
          plannedRisk: plannedRisk,
          riskPerUnit: riskPerUnit,
          estimatedRoundTripCosts: estimatedRoundTripCosts,
          executionCostToRiskPercent: executionCostToRiskPercent,
          portfolioRiskAfter: portfolioRiskAfter,
          symbolRiskAfter: symbolRiskAfter,
        );

    if (quantity < rules.minimumQuantity || quantity <= 0) {
      return rejectSized(CanonicalDecisionRejection.quantityBelowMinimum);
    }
    if (quantity > rules.maximumMarketQuantity) {
      return rejectSized(CanonicalDecisionRejection.quantityAboveMaximum);
    }
    if (notional < rules.minimumNotional) {
      return rejectSized(CanonicalDecisionRejection.notionalBelowMinimum);
    }
    if (bufferedMarginRequirement > input.availableMargin + 0.0000001) {
      return rejectSized(CanonicalDecisionRejection.insufficientMargin);
    }
    if (executionCostToRiskPercent > economics.maximumCostToRiskPercent) {
      return rejectSized(CanonicalDecisionRejection.executionCostToRiskTooHigh);
    }
    if (portfolioRiskAfter > input.portfolio.portfolioRiskLimit) {
      return rejectSized(CanonicalDecisionRejection.portfolioRiskLimit);
    }
    if (symbolRiskAfter > input.portfolio.symbolHeatLimit) {
      return rejectSized(CanonicalDecisionRejection.symbolHeatLimit);
    }

    return _record(
      disposition: CanonicalDecisionDisposition.eligible,
      rejection: CanonicalDecisionRejection.none,
      decisionKey: decisionKey,
      plan: plan,
      provenance: provenance,
      rules: rules,
      economics: economics,
      referenceEntry: input.marketPrice,
      normalizedEntry: normalizedEntry,
      normalizedStop: normalizedStop,
      quantity: quantity,
      notional: notional,
      leverage: leverage,
      requiredMargin: requiredMargin,
      bufferedMarginRequirement: bufferedMarginRequirement,
      riskBudget: riskBudget,
      plannedRisk: plannedRisk,
      riskPerUnit: riskPerUnit,
      estimatedRoundTripCosts: estimatedRoundTripCosts,
      executionCostToRiskPercent: executionCostToRiskPercent,
      portfolioRiskAfter: portfolioRiskAfter,
      symbolRiskAfter: symbolRiskAfter,
      reasonCodes: [...reasons, 'eligible'],
    );
  }

  static CanonicalDecisionRecord _record({
    required CanonicalDecisionDisposition disposition,
    required CanonicalDecisionRejection rejection,
    required String decisionKey,
    required CanonicalOpportunityPlan plan,
    required CanonicalDecisionProvenance provenance,
    required CanonicalInstrumentRules rules,
    required CanonicalExecutionEconomics economics,
    required double referenceEntry,
    required double normalizedEntry,
    required double normalizedStop,
    required double quantity,
    required double notional,
    required int leverage,
    required double requiredMargin,
    required double bufferedMarginRequirement,
    required double riskBudget,
    required double plannedRisk,
    required double riskPerUnit,
    required double estimatedRoundTripCosts,
    required double executionCostToRiskPercent,
    required double portfolioRiskAfter,
    required double symbolRiskAfter,
    required Iterable<String> reasonCodes,
  }) {
    final fingerprintPayload = <String, Object?>{
      'decisionKey': decisionKey,
      'disposition': disposition.name,
      'rejection': rejection.name,
      'pipelineVersion': version,
      'marketDatasetSource': provenance.marketDatasetSource,
      'marketDatasetVersion': provenance.marketDatasetVersion,
      'strategyConfigId': provenance.strategyConfigId,
      'sourceBuild': provenance.sourceBuild,
      'versions': provenance.versions.toJson(),
      'instrumentRulesKnown': rules.exchangeRulesKnown,
      'referenceEntry': referenceEntry,
      'normalizedEntry': normalizedEntry,
      'normalizedStop': normalizedStop,
      'quantity': quantity,
      'notional': notional,
      'leverage': leverage,
      'requiredMargin': requiredMargin,
      'bufferedMarginRequirement': bufferedMarginRequirement,
      'riskBudget': riskBudget,
      'plannedRisk': plannedRisk,
      'riskPerUnit': riskPerUnit,
      'estimatedRoundTripCosts': estimatedRoundTripCosts,
      'executionCostToRiskPercent': executionCostToRiskPercent,
      'portfolioRiskAfter': portfolioRiskAfter,
      'symbolRiskAfter': symbolRiskAfter,
      'economics': economics.toJson(),
      'reasonCodes': reasonCodes.toList(growable: false),
    };
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(fingerprintPayload)))
        .toString();
    return CanonicalDecisionRecord(
      disposition: disposition,
      rejection: rejection,
      decisionKey: decisionKey,
      preExecutionFingerprint: fingerprint,
      plan: plan,
      provenance: provenance,
      instrumentRulesKnown: rules.exchangeRulesKnown,
      referenceEntry: referenceEntry,
      normalizedEntry: normalizedEntry,
      normalizedStop: normalizedStop,
      quantity: quantity,
      notional: notional,
      leverage: leverage,
      requiredMargin: requiredMargin,
      bufferedMarginRequirement: bufferedMarginRequirement,
      riskBudget: riskBudget,
      plannedRisk: plannedRisk,
      riskPerUnit: riskPerUnit,
      estimatedRoundTripCosts: estimatedRoundTripCosts,
      executionCostToRiskPercent: executionCostToRiskPercent,
      portfolioRiskAfter: portfolioRiskAfter,
      symbolRiskAfter: symbolRiskAfter,
      economics: economics,
      reasonCodes: reasonCodes,
    );
  }

  static String _decisionKey(
    CanonicalOpportunityPlan plan,
    String strategyConfigId,
  ) => [
    plan.symbol,
    plan.timeframe,
    plan.strategy,
    plan.strategyVersion,
    plan.setupId,
    plan.createdAtUtc.toIso8601String(),
    strategyConfigId,
  ].join('|');

  static double _roundPrice(double value, int precision) {
    final factor = math.pow(10, precision).toDouble();
    return (value * factor).round() / factor;
  }

  static double _roundQuantityDown(double value, int precision) {
    final factor = math.pow(10, precision).toDouble();
    return (value * factor).floorToDouble() / factor;
  }
}
