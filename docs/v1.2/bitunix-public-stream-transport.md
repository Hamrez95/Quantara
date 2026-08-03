# Quantara v1.2 — Bitunix Public Stream Transport

Related issues: #101, #102, #112 and Epic #113.

## Scope

This slice connects only to the Bitunix public Futures WebSocket endpoint. It does not authenticate, read an account, hold credentials, call private channels or place/cancel orders.

The transport consumes the protocol and validation layer introduced by the public-stream protocol slice.

## Connection lifecycle

Each subscription shard owns one independent connection with the following states:

`idle → connecting → live → backingOff → connecting ... → stopped`

The connection:

1. creates a socket for the configured secure `wss` endpoint;
2. waits for the socket-ready future with a bounded timeout;
3. sends the shard subscription through the shared outbound rate schedule;
4. decodes and validates inbound public messages;
5. reports faults without allowing diagnostic callbacks to crash the loop;
6. closes and reconnects after unexpected termination, silence or repeated malformed payloads;
7. stops explicitly without reconnecting.

## Reconnect policy

Reconnect delay uses exponential backoff with a deterministic shard-aware jitter and a configured cap. A connection that delivered a valid payload resets the exponential attempt count before the next reconnect.

Each shard reconnects independently; one failed symbol group does not stop unrelated shards.

## Health and heartbeat

A periodic application ping uses the same five-message-per-second outbound schedule as subscribe and unsubscribe traffic. The transport tracks the last inbound message timestamp. A connection exceeding the silence timeout is reported and closed so the reconnect loop can restore it.

Heartbeat exceptions are guarded. An asynchronous timer callback cannot leak an unhandled error into the Flutter zone.

## Inbound trust boundary

Every text payload is passed through `BitunixPublicStreamCodec`. Non-text frames and malformed payloads consume a bounded consecutive-fault budget. When the budget is exceeded the socket closes with an unsupported-data code and reconnects.

A valid control or market payload resets the consecutive malformed count. Event callback failures are reported but do not corrupt the transport or suppress later market events.

## Backpressure and ordering

Outbound operations are serialized and wait for their reserved UTC send slot. Reconnect and heartbeat cannot bypass the official pacing contract.

Inbound messages are consumed in socket order. Higher-level coalescing and candidate delivery are separate slices; this transport does not mutate candidate, journal or execution state directly.

## Test strategy

Transport tests use deterministic fake sockets rather than the public internet. They cover:

- subscription only after socket readiness;
- validated event delivery;
- clean stop;
- unexpected-close reconnect and backoff;
- malformed-payload budget closure;
- callback-failure isolation;
- secure-endpoint rejection;
- reconnect delay cap and deterministic jitter.

A later staging/shadow gate will exercise the real public endpoint without enabling private exchange authority.
