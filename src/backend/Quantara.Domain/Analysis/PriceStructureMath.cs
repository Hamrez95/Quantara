using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Analysis;

internal static class PriceStructureMath
{
    public static bool IsValid(PriceStructureSpecification specification)
    {
        return specification.PivotRadius is >= 1 and <= 20
            && specification.AtrPeriod is >= 2 and <= 500
            && specification.MinimumTouches is >= 2 and <= 20
            && specification.ZoneAtrMultiplier is > 0m and <= 5m
            && specification.MinimumZoneWidthBps is > 0m and <= 500m
            && specification.BreakoutAtrMultiplier is > 0m and <= 10m
            && specification.RecencyHalfLifeBars is >= 2 and <= 10000
            && specification.MaximumZones is >= 1 and <= 50;
    }

    public static (PriceStructureBuildCode Code, string Message) ValidateCandles(
        IReadOnlyList<Candle> candles)
    {
        var first = candles[0];
        if (!first.IsValid || first.Timeframe <= TimeSpan.Zero)
        {
            return (PriceStructureBuildCode.InvalidCandle, "Every candle must be valid.");
        }

        var previousOpenTime = first.OpenTime.ToUniversalTime();
        for (var index = 1; index < candles.Count; index++)
        {
            var candle = candles[index];
            if (!candle.IsValid || candle.Timeframe <= TimeSpan.Zero)
            {
                return (PriceStructureBuildCode.InvalidCandle, "Every candle must be valid.");
            }

            if (!StringComparer.Ordinal.Equals(candle.Symbol.Value, first.Symbol.Value))
            {
                return (PriceStructureBuildCode.MixedSymbol, "All candles must use one symbol.");
            }

            if (candle.Timeframe != first.Timeframe)
            {
                return (PriceStructureBuildCode.MixedTimeframe, "All candles must use one timeframe.");
            }

            var openTime = candle.OpenTime.ToUniversalTime();
            if (openTime == previousOpenTime)
            {
                return (PriceStructureBuildCode.DuplicateCandle, "Duplicate candle open times are not allowed.");
            }

            if (openTime < previousOpenTime)
            {
                return (PriceStructureBuildCode.UnorderedCandle, "Candles must be ordered by open time.");
            }

            if (openTime != previousOpenTime + first.Timeframe)
            {
                return (PriceStructureBuildCode.MissingCandle, "The candle sequence contains a missing interval.");
            }

            previousOpenTime = openTime;
        }

        return (PriceStructureBuildCode.Created, "Candles are valid.");
    }

    public static decimal[] CalculateTrueRanges(IReadOnlyList<Candle> candles)
    {
        var result = new decimal[candles.Count];
        result[0] = candles[0].High - candles[0].Low;
        for (var index = 1; index < candles.Count; index++)
        {
            var candle = candles[index];
            var previousClose = candles[index - 1].Close;
            result[index] = Math.Max(
                candle.High - candle.Low,
                Math.Max(
                    Math.Abs(candle.High - previousClose),
                    Math.Abs(candle.Low - previousClose)));
        }

        return result;
    }

    public static decimal[] CalculateRollingAverages(
        IReadOnlyList<decimal> values,
        int period)
    {
        var result = new decimal[values.Count];
        var runningSum = 0m;
        for (var index = 0; index < values.Count; index++)
        {
            runningSum += values[index];
            if (index >= period)
            {
                runningSum -= values[index - period];
            }

            result[index] = runningSum / Math.Min(index + 1, period);
        }

        return result;
    }

    public static bool IsConfirmedHigh(
        IReadOnlyList<Candle> candles,
        int index,
        int radius)
    {
        var value = candles[index].High;
        for (var offset = 1; offset <= radius; offset++)
        {
            if (value <= candles[index - offset].High
                || value < candles[index + offset].High)
            {
                return false;
            }
        }

        return true;
    }

    public static bool IsConfirmedLow(
        IReadOnlyList<Candle> candles,
        int index,
        int radius)
    {
        var value = candles[index].Low;
        for (var offset = 1; offset <= radius; offset++)
        {
            if (value >= candles[index - offset].Low
                || value > candles[index + offset].Low)
            {
                return false;
            }
        }

        return true;
    }

    public static string ComputeHash(Action<StringBuilder> writeCanonicalContent)
    {
        ArgumentNullException.ThrowIfNull(writeCanonicalContent);
        var builder = new StringBuilder();
        writeCanonicalContent(builder);
        var bytes = Encoding.UTF8.GetBytes(builder.ToString());
        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }

    public static void Append(StringBuilder builder, string value)
    {
        builder.Append(value.Length.ToString(CultureInfo.InvariantCulture));
        builder.Append(':');
        builder.Append(value);
        builder.Append('\n');
    }

    public static void Append(StringBuilder builder, int value) =>
        Append(builder, value.ToString(CultureInfo.InvariantCulture));

    public static void Append(StringBuilder builder, long value) =>
        Append(builder, value.ToString(CultureInfo.InvariantCulture));

    public static void Append(StringBuilder builder, decimal value) =>
        Append(builder, value.ToString("G29", CultureInfo.InvariantCulture));

    public static decimal RoundPrice(decimal value) =>
        decimal.Round(value, 8, MidpointRounding.ToEven);

    public static decimal RoundScore(decimal value) =>
        decimal.Round(value, 6, MidpointRounding.ToEven);
}

