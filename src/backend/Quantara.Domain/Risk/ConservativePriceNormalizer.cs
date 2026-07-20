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

    public static decimal NormalizeDown(decimal price, decimal tickSize, int precision)
    {
        if (price <= 0m || tickSize <= 0m || precision is < 0 or > 28)
        {
            return 0m;
        }

        var steppedPrice = decimal.Floor(price / tickSize) * tickSize;
        return decimal.Round(steppedPrice, precision, MidpointRounding.ToZero);
    }

    public static decimal NormalizeUp(decimal price, decimal tickSize, int precision)
    {
        if (price <= 0m || tickSize <= 0m || precision is < 0 or > 28)
        {
            return 0m;
        }

        var steppedPrice = decimal.Ceiling(price / tickSize) * tickSize;
        return decimal.Round(steppedPrice, precision, MidpointRounding.ToZero);
    }

    public static bool IsTickCompatibleWithPrecision(decimal tickSize, int precision)
    {
        if (tickSize <= 0m || precision is < 0 or > 28)
        {
            return false;
        }

        var text = tickSize
            .ToString(CultureInfo.InvariantCulture)
            .TrimEnd('0')
            .TrimEnd('.');
        var decimalSeparatorIndex = text.IndexOf('.', StringComparison.Ordinal);
        var effectiveScale = decimalSeparatorIndex < 0
            ? 0
            : text.Length - decimalSeparatorIndex - 1;

        return effectiveScale <= precision;
    }
}
