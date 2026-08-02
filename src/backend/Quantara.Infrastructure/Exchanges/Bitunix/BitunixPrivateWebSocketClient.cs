using System.Globalization;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Quantara.Infrastructure.Exchanges.Bitunix;

public interface IBitunixPrivateEventSink
{
    Task OnConnectionStateChangedAsync(
        BitunixPrivateConnectionState state,
        string reason,
        CancellationToken cancellationToken);

    Task OnEventAsync(
        BitunixPrivateStreamEvent streamEvent,
        CancellationToken cancellationToken);
}

public sealed class BitunixPrivateWebSocketClient
{
    private const int MaximumMessageBytes = 1_048_576;
    private static readonly Uri DefaultEndpoint =
        new("wss://fapi.bitunix.com/private/");

    private readonly TimeProvider _timeProvider;
    private readonly Uri _endpoint;

    public BitunixPrivateWebSocketClient(
        TimeProvider timeProvider,
        Uri? endpoint = null)
    {
        _timeProvider = timeProvider;
        _endpoint = endpoint ?? DefaultEndpoint;
        if (_endpoint.Scheme != "wss")
        {
            throw new ArgumentException(
                "Bitunix private WebSocket requires a wss endpoint.",
                nameof(endpoint));
        }
    }

    public async Task RunAsync(
        BitunixCredentials credentials,
        IBitunixPrivateEventSink sink,
        CancellationToken cancellationToken)
    {
        credentials.Validate();
        ArgumentNullException.ThrowIfNull(sink);
        var attempt = 0;
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await RunConnectionAsync(credentials, sink, cancellationToken)
                    .ConfigureAwait(false);
                attempt = 0;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (WebSocketException exception)
            {
                attempt++;
                await ReportReconnectAsync(
                        sink,
                        "Private WebSocket disconnected: " + exception.WebSocketErrorCode,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (BitunixSafeException exception)
            {
                attempt++;
                await ReportReconnectAsync(
                        sink,
                        exception.Message,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (JsonException)
            {
                attempt++;
                await ReportReconnectAsync(
                        sink,
                        "Private WebSocket returned malformed JSON.",
                        cancellationToken)
                    .ConfigureAwait(false);
            }

            var delay = TimeSpan.FromSeconds(Math.Min(30, Math.Pow(2, Math.Min(attempt, 4))));
            await Task.Delay(delay, _timeProvider, cancellationToken).ConfigureAwait(false);
        }

        await sink
            .OnConnectionStateChangedAsync(
                BitunixPrivateConnectionState.Stopped,
                "Private WebSocket stopped.",
                CancellationToken.None)
            .ConfigureAwait(false);
    }

    private async Task RunConnectionAsync(
        BitunixCredentials credentials,
        IBitunixPrivateEventSink sink,
        CancellationToken cancellationToken)
    {
        await sink
            .OnConnectionStateChangedAsync(
                BitunixPrivateConnectionState.Connecting,
                "Connecting to Bitunix private WebSocket.",
                cancellationToken)
            .ConfigureAwait(false);

        using var socket = new ClientWebSocket();
        socket.Options.KeepAliveInterval = TimeSpan.FromSeconds(20);
        await socket.ConnectAsync(_endpoint, cancellationToken).ConfigureAwait(false);

        await sink
            .OnConnectionStateChangedAsync(
                BitunixPrivateConnectionState.Authenticating,
                "Authenticating private stream.",
                cancellationToken)
            .ConfigureAwait(false);

        var timestamp = _timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
        var login = BitunixPrivateWebSocketProtocol.CreateLoginMessage(
            credentials,
            CreateNonce(),
            timestamp);
        await SendTextAsync(socket, login, cancellationToken).ConfigureAwait(false);

        using var loginTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        loginTimeout.CancelAfter(TimeSpan.FromSeconds(12));
        var loginResponse = await ReceiveJsonAsync(socket, loginTimeout.Token)
            .ConfigureAwait(false);
        BitunixPrivateWebSocketProtocol.EnsureLoginAccepted(loginResponse);

        await sink
            .OnConnectionStateChangedAsync(
                BitunixPrivateConnectionState.Subscribing,
                "Subscribing to balance, order, position, and TP/SL events.",
                cancellationToken)
            .ConfigureAwait(false);
        await SendTextAsync(
                socket,
                BitunixPrivateWebSocketProtocol.CreateSubscriptionMessage(),
                cancellationToken)
            .ConfigureAwait(false);

        await sink
            .OnConnectionStateChangedAsync(
                BitunixPrivateConnectionState.Healthy,
                "Private reconciliation stream is healthy.",
                cancellationToken)
            .ConfigureAwait(false);

        using var heartbeatCancellation =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var heartbeat = HeartbeatLoopAsync(
            socket,
            heartbeatCancellation.Token);
        try
        {
            while (socket.State == WebSocketState.Open
                   && !cancellationToken.IsCancellationRequested)
            {
                var root = await ReceiveJsonAsync(socket, cancellationToken)
                    .ConfigureAwait(false);
                var streamEvent = BitunixPrivateWebSocketProtocol.TryParseEvent(
                    root,
                    _timeProvider.GetUtcNow());
                if (streamEvent is not null)
                {
                    await sink
                        .OnEventAsync(streamEvent, cancellationToken)
                        .ConfigureAwait(false);
                }
            }
        }
        finally
        {
            heartbeatCancellation.Cancel();
            try
            {
                await heartbeat.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }

            if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
            {
                await socket.CloseOutputAsync(
                        WebSocketCloseStatus.NormalClosure,
                        "Quantara reconnecting or stopping.",
                        CancellationToken.None)
                    .ConfigureAwait(false);
            }
        }
    }

    private async Task HeartbeatLoopAsync(
        ClientWebSocket socket,
        CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(20), _timeProvider);
        while (await timer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false))
        {
            if (socket.State != WebSocketState.Open)
            {
                return;
            }

            var unixSeconds = _timeProvider
                .GetUtcNow()
                .ToUnixTimeSeconds();
            await SendTextAsync(
                    socket,
                    BitunixPrivateWebSocketProtocol.CreatePingMessage(unixSeconds),
                    cancellationToken)
                .ConfigureAwait(false);
        }
    }

    private static async Task<JsonElement> ReceiveJsonAsync(
        ClientWebSocket socket,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        using var stream = new MemoryStream();
        WebSocketReceiveResult result;
        do
        {
            result = await socket
                .ReceiveAsync(buffer, cancellationToken)
                .ConfigureAwait(false);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                throw new WebSocketException(
                    WebSocketError.ConnectionClosedPrematurely,
                    "Bitunix private WebSocket closed the connection.");
            }

            if (result.MessageType != WebSocketMessageType.Text)
            {
                continue;
            }

            await stream
                .WriteAsync(buffer.AsMemory(0, result.Count), cancellationToken)
                .ConfigureAwait(false);
            if (stream.Length > MaximumMessageBytes)
            {
                throw new BitunixSafeException(
                    "Bitunix private WebSocket returned an oversized message.");
            }
        }
        while (!result.EndOfMessage);

        stream.Position = 0;
        using var document = await JsonDocument
            .ParseAsync(stream, cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        return document.RootElement.Clone();
    }

    private static Task SendTextAsync(
        ClientWebSocket socket,
        string content,
        CancellationToken cancellationToken)
    {
        var bytes = Encoding.UTF8.GetBytes(content);
        return socket.SendAsync(
            bytes,
            WebSocketMessageType.Text,
            true,
            cancellationToken);
    }

    private static async Task ReportReconnectAsync(
        IBitunixPrivateEventSink sink,
        string reason,
        CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested)
        {
            return;
        }

        await sink
            .OnConnectionStateChangedAsync(
                BitunixPrivateConnectionState.Reconnecting,
                reason,
                cancellationToken)
            .ConfigureAwait(false);
    }

    private static string CreateNonce() =>
        string.Concat(
            RandomNumberGenerator
                .GetBytes(16)
                .Select(value => value.ToString("x2", CultureInfo.InvariantCulture)));
}
