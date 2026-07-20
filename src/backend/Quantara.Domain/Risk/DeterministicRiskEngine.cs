using Quantara.Domain.Trading;

namespace Quantara.Domain.Risk;

public static class DeterministicRiskEngine
{
    public static RiskEvaluationResult Evaluate(
        RiskEvaluationRequest request,
        RiskPolicy policy,
        InstrumentRiskRules instrumentRules,
        CorrelationRiskContext? correlationContext = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(policy);
        ArgumentNullException.ThrowIfNull(instrumentRules);

        var validCorrelationContext = IsCorrelationContextValid(correlationContext)
            ? correlationContext
            : null;

        if (!AreInstrumentRulesValid(instrumentRules))
        {
            return CreateRejectedResult(
                request,
                policy.Version,
                RiskDecisionCode.InstrumentRuleViolation,
                new PriceNormalizationResult(0m, 0m, 0m, true),
                validCorrelationContext);
        }

        var normalizedPrices = ConservativePriceNormalizer.Normalize(
            request.Direction,
            request.EntryPrice,
            request.StopLoss,
            request.TakeProfit,
            instrumentRules.TickSize,
            instrumentRules.PricePrecision);

        if (request.IsReduceOnly)
        {
            return EvaluateReduceOnly(
                request,
                policy,
                instrumentRules,
                normalizedPrices,
                correlationContext,
                validCorrelationContext);
        }

        if (!IsPolicyValid(policy))
        {
            return CreateRejectedResult(
                request,
                policy.Version,
                RiskDecisionCode.InvalidPolicy,
                normalizedPrices,
                validCorrelationContext);
        }

        var normalizedRequest = request with
        {
            EntryPrice = normalizedPrices.EntryPrice,
            StopLoss = normalizedPrices.StopLoss,
            TakeProfit = normalizedPrices.TakeProfit
        };
        var rejectionReasons = new List<RiskDecisionCode>();
        var warnings = new List<string>();

        if (normalizedPrices.WasAdjusted)
        {
            warnings.Add("Entry, stop-loss, or take-profit was conservatively normalized to the instrument tick size.");
        }

        ValidateOpeningRequest(
            normalizedRequest,
            policy,
            instrumentRules,
            correlationContext,
            rejectionReasons);

        var stopDistance = normalizedRequest.EntryPrice > 0m
            && normalizedRequest.StopLoss > 0m
            && normalizedRequest.EntryPrice != normalizedRequest.StopLoss
                ? Math.Abs(normalizedRequest.EntryPrice - normalizedRequest.StopLoss)
                : 0m;

        var riskAmount = normalizedRequest.AccountEquity > 0m
            && normalizedRequest.RequestedRiskPercent > 0m
                ? normalizedRequest.AccountEquity * normalizedRequest.RequestedRiskPercent / 100m
                : 0m;

        var feeRate = Math.Max(normalizedRequest.RoundTripFeePercent, 0m) / 100m;
        var slippageRate = Math.Max(normalizedRequest.EstimatedSlippagePercent, 0m) / 100m;
        var entryNotionalPerUnit = normalizedRequest.EntryPrice > 0m
            ? normalizedRequest.EntryPrice * instrumentRules.ContractSize
            : 0m;
        var perUnitRisk = stopDistance > 0m
            ? stopDistance * instrumentRules.ContractSize
                + entryNotionalPerUnit * feeRate
                + entryNotionalPerUnit * slippageRate
            : 0m;

        var rawQuantity = riskAmount > 0m && perUnitRisk > 0m
            ? riskAmount / perUnitRisk
            : 0m;

        var normalizedQuantity = NormalizeQuantityDown(
            rawQuantity,
            instrumentRules.QuantityStep,
            instrumentRules.QuantityPrecision);

        if (normalizedQuantity > instrumentRules.MaximumQuantity)
        {
            normalizedQuantity = NormalizeQuantityDown(
                instrumentRules.MaximumQuantity,
                instrumentRules.QuantityStep,
                instrumentRules.QuantityPrecision);
            warnings.Add("Quantity was capped to the instrument maximum without increasing monetary risk.");
        }

        var positionNotional = normalizedQuantity * entryNotionalPerUnit;
        var requiredMargin = normalizedRequest.Leverage > 0m
            ? positionNotional / normalizedRequest.Leverage
            : 0m;
        var estimatedFees = positionNotional * feeRate;
        var estimatedSlippage = positionNotional * slippageRate;
        var portfolioExposureAfter = normalizedRequest.CurrentPortfolioExposure + positionNotional;
        var symbolExposureAfter = normalizedRequest.CurrentSymbolExposure + positionNotional;
        var allocatedCapitalAfter = normalizedRequest.CurrentAllocatedCapital + requiredMargin + estimatedFees;

        var correlationGroup = validCorrelationContext?.Group ?? string.Empty;
        var correlatedExposureBefore = validCorrelationContext?.CurrentExposure ?? 0m;
        var correlationFactor = validCorrelationContext?.ProposedExposureFactor ?? 0m;
        var correlatedExposureAfter = correlatedExposureBefore + positionNotional * correlationFactor;

        if (rawQuantity > 0m && normalizedQuantity < instrumentRules.MinimumQuantity)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.QuantityBelowMinimum);
        }

        if (positionNotional > 0m && positionNotional < instrumentRules.MinimumNotional)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.MinimumNotionalNotMet);
        }

        if (normalizedRequest.AccountEquity > 0m)
        {
            var maximumPortfolioExposure = normalizedRequest.AccountEquity
                * policy.MaximumPortfolioExposurePercent
                / 100m;
            var maximumSymbolExposure = normalizedRequest.AccountEquity
                * policy.MaximumSymbolExposurePercent
                / 100m;
            var maximumTradingAllocation = normalizedRequest.AccountEquity
                * policy.MaximumTradingAllocationPercent
                / 100m;

            if (portfolioExposureAfter > maximumPortfolioExposure)
            {
                AddUnique(rejectionReasons, RiskDecisionCode.PortfolioExposureLimitExceeded);
            }

            if (symbolExposureAfter > maximumSymbolExposure)
            {
                AddUnique(rejectionReasons, RiskDecisionCode.SymbolExposureLimitExceeded);
            }

            if (allocatedCapitalAfter > maximumTradingAllocation)
            {
                AddUnique(rejectionReasons, RiskDecisionCode.TradingAllocationExceeded);
            }

            if (validCorrelationContext is not null)
            {
                var maximumCorrelatedExposure = normalizedRequest.AccountEquity
                    * policy.MaximumCorrelatedExposurePercent
                    / 100m;
                if (correlatedExposureAfter > maximumCorrelatedExposure)
                {
                    AddUnique(rejectionReasons, RiskDecisionCode.CorrelatedExposureLimitExceeded);
                }
            }
        }

        if (requiredMargin + estimatedFees > normalizedRequest.AvailableBalance)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InsufficientAvailableBalance);
        }

        var isApproved = rejectionReasons.Count == 0;
        return new RiskEvaluationResult(
            isApproved,
            isApproved ? RiskDecisionCode.Approved : rejectionReasons[0],
            rejectionReasons.AsReadOnly(),
            warnings.AsReadOnly(),
            normalizedPrices.EntryPrice,
            normalizedPrices.StopLoss,
            normalizedPrices.TakeProfit,
            riskAmount,
            rawQuantity,
            normalizedQuantity,
            requiredMargin,
            estimatedFees,
            estimatedSlippage,
            normalizedRequest.CurrentPortfolioExposure,
            portfolioExposureAfter,
            correlationGroup,
            correlatedExposureBefore,
            correlatedExposureAfter,
            normalizedRequest.EvaluatedAt,
            policy.Version);
    }

    public static decimal NormalizeQuantityDown(decimal quantity, decimal stepSize, int precision)
    {
        return ConservativePriceNormalizer.NormalizeDown(quantity, stepSize, precision);
    }

    private static RiskEvaluationResult EvaluateReduceOnly(
        RiskEvaluationRequest request,
        RiskPolicy policy,
        InstrumentRiskRules instrumentRules,
        PriceNormalizationResult normalizedPrices,
        CorrelationRiskContext? suppliedCorrelationContext,
        CorrelationRiskContext? validCorrelationContext)
    {
        var rejectionReasons = new List<RiskDecisionCode>();
        var warnings = new List<string>();
        var rawQuantity = request.RequestedQuantity.GetValueOrDefault();
        var normalizedQuantity = NormalizeQuantityDown(
            rawQuantity,
            instrumentRules.QuantityStep,
            instrumentRules.QuantityPrecision);

        if (rawQuantity <= 0m || normalizedQuantity < instrumentRules.MinimumQuantity)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.QuantityBelowMinimum);
        }

        if (normalizedQuantity > instrumentRules.MaximumQuantity)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.QuantityAboveMaximum);
        }

        if (policy.KillSwitchEnabled)
        {
            warnings.Add("Kill switch is active; reduce-only exposure reduction remains permitted.");
        }

        if (suppliedCorrelationContext is not null && validCorrelationContext is null)
        {
            warnings.Add("Invalid correlation context was ignored for the reduce-only exposure reduction.");
        }

        var correlationGroup = validCorrelationContext?.Group ?? string.Empty;
        var correlatedExposure = validCorrelationContext?.CurrentExposure ?? 0m;
        var isApproved = rejectionReasons.Count == 0;

        return new RiskEvaluationResult(
            isApproved,
            isApproved ? RiskDecisionCode.ReduceOnlyApproved : rejectionReasons[0],
            rejectionReasons.AsReadOnly(),
            warnings.AsReadOnly(),
            normalizedPrices.EntryPrice,
            normalizedPrices.StopLoss,
            normalizedPrices.TakeProfit,
            0m,
            rawQuantity,
            normalizedQuantity,
            0m,
            0m,
            0m,
            request.CurrentPortfolioExposure,
            request.CurrentPortfolioExposure,
            correlationGroup,
            correlatedExposure,
            correlatedExposure,
            request.EvaluatedAt,
            policy.Version);
    }

    private static RiskEvaluationResult CreateRejectedResult(
        RiskEvaluationRequest request,
        string policyVersion,
        RiskDecisionCode decisionCode,
        PriceNormalizationResult normalizedPrices,
        CorrelationRiskContext? validCorrelationContext)
    {
        var correlationGroup = validCorrelationContext?.Group ?? string.Empty;
        var correlatedExposure = validCorrelationContext?.CurrentExposure ?? 0m;

        return new RiskEvaluationResult(
            false,
            decisionCode,
            new[] { decisionCode },
            Array.Empty<string>(),
            normalizedPrices.EntryPrice,
            normalizedPrices.StopLoss,
            normalizedPrices.TakeProfit,
            0m,
            0m,
            0m,
            0m,
            0m,
            0m,
            request.CurrentPortfolioExposure,
            request.CurrentPortfolioExposure,
            correlationGroup,
            correlatedExposure,
            correlatedExposure,
            request.EvaluatedAt,
            policyVersion);
    }

    private static void ValidateOpeningRequest(
        RiskEvaluationRequest request,
        RiskPolicy policy,
        InstrumentRiskRules instrumentRules,
        CorrelationRiskContext? correlationContext,
        List<RiskDecisionCode> rejectionReasons)
    {
        if (request.AccountEquity <= 0m)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidAccountEquity);
        }

        if (request.AvailableBalance < 0m)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidAvailableBalance);
        }

        if (request.RequestedRiskPercent <= 0m)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidRiskPercentage);
        }
        else if (request.RequestedRiskPercent > policy.MaximumRiskPerTradePercent)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.RiskPerTradeExceeded);
        }

        if (request.EntryPrice <= 0m)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidEntryPrice);
        }

        var hasValidStopDistance = request.StopLoss > 0m
            && request.EntryPrice > 0m
            && request.StopLoss != request.EntryPrice;
        if (!hasValidStopDistance)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidStopLoss);
        }
        else if (!HasValidStopDirection(request))
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidStopDirection);
        }

        if (request.TakeProfit <= 0m || !HasValidTakeProfitDirection(request))
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidTakeProfit);
        }
        else if (hasValidStopDistance)
        {
            var riskReward = Math.Abs(request.TakeProfit - request.EntryPrice)
                / Math.Abs(request.EntryPrice - request.StopLoss);
            if (riskReward < policy.MinimumRiskReward)
            {
                AddUnique(rejectionReasons, RiskDecisionCode.MinimumRiskRewardNotMet);
            }
        }

        if (request.SpreadPercent < 0m
            || request.EstimatedSlippagePercent < 0m
            || request.RoundTripFeePercent < 0m)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidMarketCost);
        }

        if (correlationContext is not null && !IsCorrelationContextValid(correlationContext))
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidCorrelationContext);
        }

        if (request.CurrentDailyLossPercent >= policy.MaximumDailyLossPercent)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.DailyLossLimitReached);
        }

        if (request.CurrentWeeklyLossPercent >= policy.MaximumWeeklyLossPercent)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.WeeklyLossLimitReached);
        }

        if (request.CurrentDrawdownPercent >= policy.MaximumDrawdownPercent)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.DrawdownLimitReached);
        }

        var maximumAllowedLeverage = Math.Min(policy.MaximumLeverage, instrumentRules.MaximumLeverage);
        if (request.Leverage <= 0m || request.Leverage > maximumAllowedLeverage)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.LeverageLimitExceeded);
        }

        if (request.OpenPositionCount >= policy.MaximumConcurrentPositions)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.ConcurrentPositionLimitReached);
        }

        if (request.SpreadPercent > policy.MaximumAllowedSpreadPercent)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.SpreadLimitExceeded);
        }

        if (request.EstimatedSlippagePercent > policy.MaximumAllowedSlippagePercent)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.SlippageLimitExceeded);
        }

        if (!request.MarketDataFresh)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.StaleMarketData);
        }

        if (!request.ExchangeConnected)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.ExchangeDisconnected);
        }

        if (request.CircuitBreakerActive)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.CircuitBreakerActive);
        }

        if (request.CooldownActive)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.CooldownActive);
        }

        if (policy.MaximumConsecutiveLosses > 0
            && request.ConsecutiveLosses >= policy.MaximumConsecutiveLosses)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.ConsecutiveLossLimitReached);
        }

        if (policy.KillSwitchEnabled)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.KillSwitchActive);
        }
    }

    private static bool IsPolicyValid(RiskPolicy policy)
    {
        return !string.IsNullOrWhiteSpace(policy.Version)
            && policy.MaximumRiskPerTradePercent > 0m
            && policy.MaximumDailyLossPercent > 0m
            && policy.MaximumWeeklyLossPercent > 0m
            && policy.MaximumDrawdownPercent > 0m
            && policy.MaximumLeverage > 0m
            && policy.MaximumPortfolioExposurePercent > 0m
            && policy.MaximumSymbolExposurePercent > 0m
            && policy.MaximumConcurrentPositions > 0
            && policy.MinimumRiskReward > 0m
            && policy.MaximumAllowedSpreadPercent >= 0m
            && policy.MaximumAllowedSlippagePercent >= 0m
            && policy.MaximumConsecutiveLosses >= 0
            && policy.MaximumTradingAllocationPercent > 0m
            && policy.MaximumCorrelatedExposurePercent > 0m;
    }

    private static bool AreInstrumentRulesValid(InstrumentRiskRules instrumentRules)
    {
        return instrumentRules.TickSize > 0m
            && instrumentRules.QuantityStep > 0m
            && instrumentRules.MinimumQuantity > 0m
            && instrumentRules.MaximumQuantity >= instrumentRules.MinimumQuantity
            && instrumentRules.MinimumNotional > 0m
            && instrumentRules.ContractSize > 0m
            && instrumentRules.PricePrecision is >= 0 and <= 28
            && instrumentRules.QuantityPrecision is >= 0 and <= 28
            && instrumentRules.MaximumLeverage > 0m
            && ConservativePriceNormalizer.IsIncrementCompatibleWithPrecision(
                instrumentRules.TickSize,
                instrumentRules.PricePrecision)
            && ConservativePriceNormalizer.IsIncrementCompatibleWithPrecision(
                instrumentRules.QuantityStep,
                instrumentRules.QuantityPrecision);
    }

    private static bool IsCorrelationContextValid(CorrelationRiskContext? correlationContext)
    {
        return correlationContext is not null
            && !string.IsNullOrWhiteSpace(correlationContext.Group)
            && correlationContext.CurrentExposure >= 0m
            && correlationContext.ProposedExposureFactor is >= 0m and <= 1m;
    }

    private static bool HasValidStopDirection(RiskEvaluationRequest request)
    {
        return request.Direction switch
        {
            TradeDirection.Long => request.StopLoss < request.EntryPrice,
            TradeDirection.Short => request.StopLoss > request.EntryPrice,
            _ => false
        };
    }

    private static bool HasValidTakeProfitDirection(RiskEvaluationRequest request)
    {
        return request.Direction switch
        {
            TradeDirection.Long => request.TakeProfit > request.EntryPrice,
            TradeDirection.Short => request.TakeProfit < request.EntryPrice,
            _ => false
        };
    }

    private static void AddUnique(List<RiskDecisionCode> reasons, RiskDecisionCode reason)
    {
        if (!reasons.Contains(reason))
        {
            reasons.Add(reason);
        }
    }
}
