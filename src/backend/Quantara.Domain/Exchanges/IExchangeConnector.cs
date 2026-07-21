using Quantara.Domain.Trading;

namespace Quantara.Domain.Exchanges;

public interface IExchangeConnector
{
    Task<IReadOnlyList<Instrument>> GetInstrumentsAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<Balance>> GetBalancesAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<Candle>> GetCandlesAsync(Symbol symbol, TimeSpan timeframe, DateTimeOffset startInclusive, DateTimeOffset endExclusive, CancellationToken cancellationToken);
    Task<Ticker> GetTickerAsync(Symbol symbol, CancellationToken cancellationToken);
    Task<OrderBook> GetOrderBookAsync(Symbol symbol, CancellationToken cancellationToken);
    Task<FundingRate> GetFundingRateAsync(Symbol symbol, CancellationToken cancellationToken);
    Task<IReadOnlyList<Position>> GetOpenPositionsAsync(CancellationToken cancellationToken);
    Task<IReadOnlyList<Order>> GetOpenOrdersAsync(CancellationToken cancellationToken);
    Task<OrderSubmissionResult> PlaceOrderAsync(OrderRequest request, CancellationToken cancellationToken);
    Task CancelOrderAsync(string clientOrderId, CancellationToken cancellationToken);
    Task<OrderSubmissionResult> ModifyOrderAsync(OrderModification request, CancellationToken cancellationToken);
    Task PlaceOrModifyProtectionAsync(ProtectionRequest request, CancellationToken cancellationToken);
    Task CloseOrReducePositionAsync(ClosePositionRequest request, CancellationToken cancellationToken);
    IAsyncEnumerable<Ticker> SubscribeTickerAsync(Symbol symbol, CancellationToken cancellationToken);
    IAsyncEnumerable<Candle> SubscribeCandlesAsync(Symbol symbol, TimeSpan timeframe, CancellationToken cancellationToken);
    IAsyncEnumerable<Order> SubscribeOrdersAsync(CancellationToken cancellationToken);
    IAsyncEnumerable<Balance> SubscribeBalancesAsync(CancellationToken cancellationToken);
    IAsyncEnumerable<Position> SubscribePositionsAsync(CancellationToken cancellationToken);
    Task<ReconciliationReport> ReconcileAsync(CancellationToken cancellationToken);
}

public sealed record Instrument(Symbol Symbol, decimal TickSize, decimal StepSize, decimal MinimumQuantity, decimal MaximumLeverage);
public sealed record Balance(string Asset, decimal Available, decimal Total);
public sealed record Ticker(Symbol Symbol, decimal LastPrice, decimal Bid, decimal Ask, DateTimeOffset Timestamp);
public sealed record OrderBook(Symbol Symbol, IReadOnlyList<BookLevel> Bids, IReadOnlyList<BookLevel> Asks, DateTimeOffset Timestamp);
public sealed record BookLevel(decimal Price, decimal Quantity);
public sealed record FundingRate(Symbol Symbol, decimal Rate, DateTimeOffset FundingTime);
public sealed record Position(Symbol Symbol, TradeDirection Direction, decimal Quantity, decimal EntryPrice, decimal UnrealizedPnl);
public sealed record Order(string ClientOrderId, Symbol Symbol, OrderSide Side, OrderType Type, decimal Quantity, decimal? LimitPrice, decimal FilledQuantity, string State);
public sealed record OrderRequest(string ClientOrderId, Symbol Symbol, OrderSide Side, OrderType Type, decimal Quantity, decimal? LimitPrice, bool ReduceOnly);
public sealed record OrderModification(string ClientOrderId, decimal? NewLimitPrice, decimal? NewQuantity);
public sealed record ProtectionRequest(Symbol Symbol, decimal StopLoss, IReadOnlyList<TakeProfitTarget> TakeProfits);
public sealed record ClosePositionRequest(Symbol Symbol, decimal Quantity, bool ReduceOnly);
public sealed record OrderSubmissionResult(string ClientOrderId, string ExchangeOrderId, string State);
public sealed record ReconciliationReport(DateTimeOffset ReconciledAt, int LocalOrderCount, int RemoteOrderCount, IReadOnlyList<string> Differences);

