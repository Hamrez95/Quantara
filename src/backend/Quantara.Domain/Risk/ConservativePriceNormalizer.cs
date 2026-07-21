using System.Globalization;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Risk;

public sealed record PriceNormalizationResult(
    decimal EntryPrice,
    decimal StopLoss,
    decimal TakeProfit,
    bool WasAdjusted);

public static class ConservativePriceNormalizer
{
    public static PriceNormalizationResult Normalize(
        TradeDirection direction,
        decimal entryPrice,
        decimal stopLoss,
        decimal takeProfit,
        decimal tickSize,
        int precision)
    {
        if (tickSize <= 0m || precision is < 0 or > 28)
        {
            return new PriceNormalizationResult(0m, 0m, 0m, true);
        }

        var normalized = direction switch
        {
            TradeDirection.Long => new PriceNormalizationResult(
                NormalizeUp(entryPrice, tickSize, precision),
                NormalizeDown(stopLoss, tickSize, precision),
                NormalizeDown(takeProfit, tickSize, precision),
                false),
            TradeDirection.Short => new PriceNormalizationResult(
                NormalizeDown(entryPrice, tickSize, precision),
                NormalizeUp(stopLoss, tickSize, precision),
                NormalizeUp(takeProfit, tickSize, precision),
                false),
            _ => new PriceNormalizationResult(0m, 0m, 0m, true)
        };

        return normalized with
        {
            WasAdjusted = normalized.EntryPrice != entryPrice
                || normalized.StopLoss != stopLoss
                || normalized.TakeProfit != takeProfit
        };
    }

    public static decimal NormalizeDown(decimal value, decimal increment, int precision)
    {
        if (value <= 0m || increment <= 0m || precision is < 0 or > 28)
        {
            return 0m;
        }

        var steppedValue = decimal.Floor(value / increment) * increment;
        return decimal.Round(steppedValue, precision, MidpointRounding.ToZero);
    }

    public static decimal NormalizeUp(decimal value, decimal increment, int precision)
    {
        if (value <= 0m || increment <= 0m || precision is < 0 or > 28)
        {
            return 0m;
        }

        var steppedValue = decimal.Ceiling(value / increment) * increment;
        return decimal.Round(steppedValue, precision, MidpointRounding.ToZero);
    }

    public static bool IsIncrementCompatibleWithPrecision(decimal increment, int precision)
    {
        if (increment <= 0m || precision is < 0 or > 28)
        {
            return false;
        }

        var text = increment
            .ToString(CultureInfo.InvariantCulture)
            .TrimEnd('0')
            .TrimEnd('.');
        var decimalSeparatorIndex = text.IndexOf('.');
        var effectiveScale = decimalSeparatorIndex < 0
            ? 0
            : text.Length - decimalSeparatorIndex - 1;

        return effectiveScale <= precision;
    }
}
