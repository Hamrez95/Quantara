using Quantara.Domain.Exchanges;
using Quantara.Domain.Trading;

namespace Quantara.Infrastructure.Exchanges;

public sealed class DeterministicMockExchangeConnector : IExchangeConnector
{
    private readonly List<Order> _orders = [];
    private readonly DateTimeOffset _seedTime = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    public Task<IReadOnlyList<Instrument>> GetInstrumentsAsync(CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<Instrument>>([
        new Instrument(new Symbol("BTCUSDT"), 0.1m, 0.001m, 0.001m, 20m),
        new Instrument(new Symbol("ETHUSDT"), 0.01m, 0.001m, 0.001m, 20m)
    ]);

    public Task<IReadOnlyList<Balance>> GetBalancesAsync(CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<Balance>>([new Balance("USDT", 100_000m, 100_000m)]);

    public Task<IReadOnlyList<Candle>> GetCandlesAsync(Symbol symbol, TimeSpan timeframe, DateTimeOffset startInclusive, DateTimeOffset endExclusive, CancellationToken cancellationToken)
    {
        var candles = new List<Candle>();
        var index = 0;
        for (var time = startInclusive; time < endExclusive; time = time.Add(timeframe), index++)
        {
            var open = 50_000m + index * 10m;
            candles.Add(new Candle(symbol, time, timeframe, open, open + 100m, open - 100m, open + 25m, 1000m + index));
        }
        return Task.FromResult<IReadOnlyList<Candle>>(candles);
    }

    public Task<Ticker> GetTickerAsync(Symbol symbol, CancellationToken cancellationToken) => Task.FromResult(new Ticker(symbol, 50_025m, 50_020m, 50_030m, _seedTime));
    public Task<OrderBook> GetOrderBookAsync(Symbol symbol, CancellationToken cancellationToken) => Task.FromResult(new OrderBook(symbol, [new BookLevel(50_020m, 1.5m)], [new BookLevel(50_030m, 1.25m)], _seedTime));
    public Task<FundingRate> GetFundingRateAsync(Symbol symbol, CancellationToken cancellationToken) => Task.FromResult(new FundingRate(symbol, 0.0001m, _seedTime.AddHours(8)));
    public Task<IReadOnlyList<Position>> GetOpenPositionsAsync(CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<Position>>([]);
    public Task<IReadOnlyList<Order>> GetOpenOrdersAsync(CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<Order>>(_orders.Where(o => o.State is "Acknowledged" or "PartiallyFilled").ToList());

    public Task<OrderSubmissionResult> PlaceOrderAsync(OrderRequest request, CancellationToken cancellationToken)
    {
        if (_orders.Any(order => order.ClientOrderId == request.ClientOrderId))
        {
            return Task.FromResult(new OrderSubmissionResult(request.ClientOrderId, $"mock-{request.ClientOrderId}", "DuplicateIgnored"));
        }
        _orders.Add(new Order(request.ClientOrderId, request.Symbol, request.Side, request.Type, request.Quantity, request.LimitPrice, 0m, "Acknowledged"));
        return Task.FromResult(new OrderSubmissionResult(request.ClientOrderId, $"mock-{request.ClientOrderId}", "Acknowledged"));
    }

    public Task CancelOrderAsync(string clientOrderId, CancellationToken cancellationToken)
    {
        var index = _orders.FindIndex(order => order.ClientOrderId == clientOrderId);
        if (index >= 0) _orders[index] = _orders[index] with { State = "Cancelled" };
        return Task.CompletedTask;
    }

    public Task<OrderSubmissionResult> ModifyOrderAsync(OrderModification request, CancellationToken cancellationToken) => Task.FromResult(new OrderSubmissionResult(request.ClientOrderId, $"mock-{request.ClientOrderId}", "Modified"));
    public Task PlaceOrModifyProtectionAsync(ProtectionRequest request, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task CloseOrReducePositionAsync(ClosePositionRequest request, CancellationToken cancellationToken) => Task.CompletedTask;
    public async IAsyncEnumerable<Ticker> SubscribeTickerAsync(Symbol symbol, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken) { yield return await GetTickerAsync(symbol, cancellationToken); }
    public async IAsyncEnumerable<Candle> SubscribeCandlesAsync(Symbol symbol, TimeSpan timeframe, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken) { await foreach (var candle in ToAsync(await GetCandlesAsync(symbol, timeframe, _seedTime, _seedTime.Add(timeframe), cancellationToken))) yield return candle; }
    public async IAsyncEnumerable<Order> SubscribeOrdersAsync([System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken) { foreach (var order in _orders) { cancellationToken.ThrowIfCancellationRequested(); yield return order; await Task.Yield(); } }
    public async IAsyncEnumerable<Balance> SubscribeBalancesAsync([System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken) { yield return (await GetBalancesAsync(cancellationToken))[0]; }
    public async IAsyncEnumerable<Position> SubscribePositionsAsync([System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken) { await Task.CompletedTask; yield break; }
    public Task<ReconciliationReport> ReconcileAsync(CancellationToken cancellationToken) => Task.FromResult(new ReconciliationReport(_seedTime, _orders.Count, _orders.Count, []));

    private static async IAsyncEnumerable<T> ToAsync<T>(IEnumerable<T> items)
    {
        foreach (var item in items) { yield return item; await Task.Yield(); }
    }
}
