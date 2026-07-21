using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

internal static class PriceStructureTestData
{
    private static readonly decimal[] WaveCloses =
    [
        100m,
        102m,
        104m,
        101m,
        98m,
        96m,
        99m,
        102m,
        105m,
        101m,
        97m,
        95m
    ];

    public static IReadOnlyList<Candle> CreateWaveCandles(
        int count = 120,
        TimeSpan? timeframe = null,
        decimal cycleDrift = 0m)
    {
        var interval = timeframe ?? TimeSpan.FromHours(1);
        var start = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        var candles = new List<Candle>(count);
        var previousClose = WaveCloses[0];

        for (var index = 0; index < count; index++)
        {
            var cycle = index / WaveCloses.Length;
            var close = WaveCloses[index % WaveCloses.Length] + (cycle * cycleDrift);
            var open = index == 0 ? close : previousClose;
            candles.Add(CreateCandle(
                index,
                interval,
                start,
                open,
                close,
                Math.Max(open, close) + 1m,
                Math.Min(open, close) - 1m,
                1000m + ((index % 5) * 75m)));
            previousClose = close;
        }

        return candles;
    }

    public static IReadOnlyList<Candle> CreateOldReactionCandles()
    {
        var interval = TimeSpan.FromHours(1);
        var start = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        var candles = new List<Candle>(100);
        candles.AddRange(CreateWaveCandles(36, interval));
        var previousClose = candles[^1].Close;

        for (var index = 36; index < 100; index++)
        {
            candles.Add(CreateCandle(
                index,
                interval,
                start,
                previousClose,
                100m,
                101m,
                99m,
                900m));
            previousClose = 100m;
        }

        return candles;
    }

    public static IReadOnlyList<Candle> CreateRecentReactionCandles()
    {
        var interval = TimeSpan.FromHours(1);
        var start = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        var candles = new List<Candle>(100);
        var previousClose = 100m;

        for (var index = 0; index < 64; index++)
        {
            candles.Add(CreateCandle(
                index,
                interval,
                start,
                previousClose,
                100m,
                101m,
                99m,
                900m));
            previousClose = 100m;
        }

        var wave = CreateWaveCandles(36, interval);
        for (var index = 0; index < wave.Count; index++)
        {
            var source = wave[index];
            candles.Add(source with
            {
                OpenTime = start + (interval * (64 + index)),
                Open = index == 0 ? previousClose : source.Open
            });
        }

        return candles;
    }

    public static IReadOnlyList<Candle> CreateBrokenResistanceCandles()
    {
        var candles = CreateWaveCandles(96).ToList();
        var interval = candles[0].Timeframe;
        var start = candles[0].OpenTime;
        var previousClose = candles[^1].Close;

        for (var index = 96; index < 120; index++)
        {
            var close = 111m + ((index - 96) % 3);
            candles.Add(CreateCandle(
                index,
                interval,
                start,
                previousClose,
                close,
                Math.Max(previousClose, close) + 0.8m,
                Math.Min(previousClose, close) - 0.8m,
                1400m));
            previousClose = close;
        }

        return candles;
    }

    public static Candle CreateCandle(
        int index,
        TimeSpan timeframe,
        DateTimeOffset start,
        decimal open,
        decimal close,
        decimal high,
        decimal low,
        decimal volume)
    {
        return new Candle(
            new Symbol("BTCUSDT"),
            start + (timeframe * index),
            timeframe,
            open,
            high,
            low,
            close,
            volume);
    }
}

