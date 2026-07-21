using Quantara.Domain.Exchanges;
using Quantara.Domain.Trading;
using Quantara.Infrastructure.Exchanges;

namespace Quantara.Domain.Tests;

public sealed class DeterministicMockExchangeConnectorTests
{
    [Fact]
    public async Task GetCandlesAsyncReturnsRepeatableValidCandles()
    {
        var connector = new DeterministicMockExchangeConnector();
        var from = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        var candles = await connector.GetCandlesAsync(new Symbol("BTCUSDT"), TimeSpan.FromMinutes(1), from, from.AddMinutes(3), CancellationToken.None);
        Assert.Equal(3, candles.Count);
        Assert.All(candles, candle => Assert.True(candle.IsValid));
        Assert.Equal(50_025m, candles[0].Close);
    }

    [Fact]
    public async Task PlaceOrderAsyncIsIdempotentByClientOrderId()
    {
        var connector = new DeterministicMockExchangeConnector();
        var request = new OrderRequest("client-1", new Symbol("BTCUSDT"), OrderSide.Buy, OrderType.Limit, 1m, 50_000m, false);
        var first = await connector.PlaceOrderAsync(request, CancellationToken.None);
        var second = await connector.PlaceOrderAsync(request, CancellationToken.None);
        Assert.Equal("Acknowledged", first.State);
        Assert.Equal("DuplicateIgnored", second.State);
    }
}

