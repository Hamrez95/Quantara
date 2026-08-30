# Quantara v1.2 — Bitunix Public Stream Protocol

Related issues: #101, #102, #112 and Epic #113.

## Scope

This slice defines the read-only public market-data contract used by the future realtime transport. It contains no API key, authentication, private channel, account payload or order authority.

The official Bitunix Futures WebSocket contract currently specifies:

- public endpoint `wss://fapi.bitunix.com/public/`;
- at most five outbound messages per second, including ping, pong, subscribe and unsubscribe messages;
- at most 300 channel subscriptions per connection;
- Kline snapshots followed by updates approximately every 500 ms;
- explicit unsubscribe before changing a Kline interval on an existing connection.

## Supported channels

The initial protocol supports the market-data channels required by candidate discovery and validation:

- market Kline: 5m, 15m, 1h, 4h and 1D;
- single ticker and aggregated tickers;
- public trades;
- depth book 1, 5, 15 and full updates;
- application ping/pong.

Other channels remain unsupported until their official schema is captured in fixtures and tests.

## Subscription planning

`BitunixSubscriptionPlanner`:

- normalizes and deduplicates subscription identities;
- sorts them deterministically;
- creates shards containing at most 300 subscriptions;
- returns no connection for an empty universe.

Each shard becomes one public WebSocket connection in the transport slice.

## Outbound pacing

`BitunixOutboundMessageSchedule` reserves messages with at least 200 ms spacing. The future socket adapter must wait until the reserved UTC instant before sending. Reconnect, ping and subscription messages share the same schedule; no control path may bypass the official five-message limit.

## Decoder trust boundary

`BitunixPublicStreamCodec` rejects rather than partially trusts:

- empty or oversized payloads;
- malformed JSON and unsupported channels;
- invalid symbols and timestamps;
- impossible OHLC or ticker ranges;
- crossed best bid/ask or crossed depth books;
- invalid trade side, time, price or quantity;
- excessive ticker, trade or depth batches.

A subscription acknowledgement is control-plane data and produces no market event. Market events preserve exchange and receive timestamps so downstream latency and stale-data gates can be measured.

## Candle time

The public Kline payload contains the push timestamp but not a separate candle-open field. Quantara derives the UTC candle open by flooring the exchange timestamp to the subscribed interval. Candle-close confirmation remains the responsibility of the event assembler and must be based on rollover or REST reconciliation, never on an in-progress Kline update alone.

## Next slice

The transport slice will add:

- cross-platform WebSocket connection and reconnect/backoff;
- bounded inbound buffering and coalescing;
- ping health and silence timeout;
- REST bootstrap and gap backfill;
- closed-candle assembly;
- delivery into the audited candidate coordinator.
