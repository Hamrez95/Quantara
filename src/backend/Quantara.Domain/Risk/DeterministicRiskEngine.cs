namespace Quantara.Domain.Risk;

public static class DeterministicRiskEngine
{
    public static RiskEvaluationResult Evaluate(
        RiskEvaluationRequest request,
        RiskPolicy policy,
        InstrumentRiskRules instrumentRules)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(policy);
        ArgumentNullException.ThrowIfNull(instrumentRules);

        var rejectionReasons = new List<RiskDecisionCode>();
        var warnings = new List<string>();

        if (!IsPolicyValid(policy))
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InvalidPolicy);
        }

        if (!AreInstrumentRulesValid(instrumentRules))
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InstrumentRuleViolation);
        }

        if (request.IsReduceOnly)
        {
            return EvaluateReduceOnly(request, policy, instrumentRules, rejectionReasons, warnings);
        }

        ValidateOpeningRequest(request, policy, instrumentRules, rejectionReasons);

        var stopDistance = request.EntryPrice > 0m && request.StopLoss > 0m
            ? Math.Abs(request.EntryPrice - request.StopLoss)
            : 0m;

        var riskAmount = request.AccountEquity > 0m && request.RequestedRiskPercent > 0m
            ? request.AccountEquity * request.RequestedRiskPercent / 100m
            : 0m;

        var feeRate = Math.Max(request.RoundTripFeePercent, 0m) / 100m;
        var slippageRate = Math.Max(request.EstimatedSlippagePercent, 0m) / 100m;
        var entryNotionalPerUnit = request.EntryPrice > 0m && instrumentRules.ContractSize > 0m
            ? request.EntryPrice * instrumentRules.ContractSize
            : 0m;
        var perUnitRisk = stopDistance > 0m && instrumentRules.ContractSize > 0m
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

        if (normalizedQuantity > instrumentRules.MaximumQuantity && instrumentRules.MaximumQuantity > 0m)
        {
            normalizedQuantity = NormalizeQuantityDown(
                instrumentRules.MaximumQuantity,
                instrumentRules.QuantityStep,
                instrumentRules.QuantityPrecision);
            warnings.Add("Quantity was capped to the instrument maximum without increasing monetary risk.");
        }

        var positionNotional = normalizedQuantity > 0m
            ? normalizedQuantity * entryNotionalPerUnit
            : 0m;
        var requiredMargin = request.Leverage > 0m
            ? positionNotional / request.Leverage
            : 0m;
        var estimatedFees = positionNotional * feeRate;
        var estimatedSlippage = positionNotional * slippageRate;
        var portfolioExposureAfter = request.CurrentPortfolioExposure + positionNotional;
        var symbolExposureAfter = request.CurrentSymbolExposure + positionNotional;
        var allocatedCapitalAfter = request.CurrentAllocatedCapital + requiredMargin + estimatedFees;

        if (rawQuantity > 0m && normalizedQuantity < instrumentRules.MinimumQuantity)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.QuantityBelowMinimum);
        }

        if (positionNotional > 0m && positionNotional < instrumentRules.MinimumNotional)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.MinimumNotionalNotMet);
        }

        if (normalizedQuantity > instrumentRules.MaximumQuantity)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.QuantityAboveMaximum);
        }

        if (request.AccountEquity > 0m)
        {
            var maximumPortfolioExposure = request.AccountEquity * policy.MaximumPortfolioExposurePercent / 100m;
            var maximumSymbolExposure = request.AccountEquity * policy.MaximumSymbolExposurePercent / 100m;
            var maximumTradingAllocation = request.AccountEquity * policy.MaximumTradingAllocationPercent / 100m;

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
        }

        if (requiredMargin + estimatedFees > request.AvailableBalance)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.InsufficientAvailableBalance);
        }

        var isApproved = rejectionReasons.Count == 0;
        return new RiskEvaluationResult(
            isApproved,
            isApproved ? RiskDecisionCode.Approved : rejectionReasons[0],
            rejectionReasons.AsReadOnly(),
            warnings.AsReadOnly(),
            riskAmount,
            rawQuantity,
            normalizedQuantity,
            requiredMargin,
            estimatedFees,
            estimatedSlippage,
            request.CurrentPortfolioExposure,
            portfolioExposureAfter,
            request.EvaluatedAt,
            policy.Version);
    }

    public static decimal NormalizeQuantityDown(decimal quantity, decimal stepSize, int precision)
    {
        if (quantity <= 0m || stepSize <= 0m || precision is < 0 or > 28)
        {
            return 0m;
        }

        var steppedQuantity = decimal.Floor(quantity / stepSize) * stepSize;
        return decimal.Round(steppedQuantity, precision, MidpointRounding.ToZero);
    }

    private static RiskEvaluationResult EvaluateReduceOnly(
        RiskEvaluationRequest request,
        RiskPolicy policy,
        InstrumentRiskRules instrumentRules,
        List<RiskDecisionCode> rejectionReasons,
        List<string> warnings)
    {
        var rawQuantity = request.RequestedQuantity.GetValueOrDefault();
        var normalizedQuantity = NormalizeQuantityDown(
            rawQuantity,
            instrumentRules.QuantityStep,
            instrumentRules.QuantityPrecision);

        if (rawQuantity <= 0m)
        {
            AddUnique(rejectionReasons, RiskDecisionCode.QuantityBelowMinimum);
        }

        if (normalizedQuantity < instrumentRules.MinimumQuantity)
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

        var isApproved = rejectionReasons.Count == 0;
        return new RiskEvaluationResult(
            isApproved,
            isApproved ? RiskDecisionCode.ReduceOnlyApproved : rejectionReasons[0],
            rejectionReasons.AsReadOnly(),
            warnings.AsReadOnly(),
            0m,
            rawQuantity,
            normalizedQuantity,
            0m,
            0m,
            0m,
            request.CurrentPortfolioExposure,
            request.CurrentPortfolioExposure,
            request.EvaluatedAt,
            policy.Version);
    }

    private static void ValidateOpeningRequest(
        RiskEvaluationRequest request,
        RiskPolicy policy,
        InstrumentRiskRules instrumentRules,
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

        if (request.StopLoss <= 0m || request.StopLoss == request.EntryPrice)
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
        else if (request.EntryPrice > 0m && request.StopLoss > 0m)
        {
            var riskReward = Math.Abs(request.TakeProfit - request.EntryPrice)
                / Math.Abs(request.EntryPrice - request.StopLoss);
            if (riskReward < policy.MinimumRiskReward)
            {
                AddUnique(rejectionReasons, RiskDecisionCode.MinimumRiskRewardNotMet);
            }
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
            && policy.MaximumTradingAllocationPercent > 0m;
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
            && instrumentRules.MaximumLeverage > 0m;
    }

    private static bool HasValidStopDirection(RiskEvaluationRequest request)
    {
        return request.Direction switch
        {
            Trading.TradeDirection.Long => request.StopLoss < request.EntryPrice,
            Trading.TradeDirection.Short => request.StopLoss > request.EntryPrice,
            _ => false
        };
    }

    private static bool HasValidTakeProfitDirection(RiskEvaluationRequest request)
    {
        return request.Direction switch
        {
            Trading.TradeDirection.Long => request.TakeProfit > request.EntryPrice,
            Trading.TradeDirection.Short => request.TakeProfit < request.EntryPrice,
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
