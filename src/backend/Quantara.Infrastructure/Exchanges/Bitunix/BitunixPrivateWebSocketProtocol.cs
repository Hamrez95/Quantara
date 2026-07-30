using System.Globalization;
using System.Text.Json;

namespace Quantara.Infrastructure.Exchanges.Bitunix;

public enum BitunixPrivateConnectionState
{
    Connecting,
    Authenticating,
    Subscribing,
    Healthy,
    Reconnecting,
    Stopped
}

public sealed record BitunixPrivateStreamEvent(
    string Channel,
    long ExchangeTimestamp,
    string EventType,
    JsonElement Data,
    DateTimeOffset ReceivedAt);

public static class BitunixPrivateWebSocketProtocol
{
    private static readonly string[] DefaultChannels =
    [
        "balance",
        "order",
        "position",
        "tpsl"
    ];

    public static string CreateLoginMessage(
        BitunixCredentials credentials,
        string nonce,
        long timestampMilliseconds)
    {
        credentials.Validate();
        if (string.IsNullOrWhiteSpace(nonce))
        {
            throw new ArgumentException("Nonce is required.", nameof(nonce));
        }

        if (timestampMilliseconds <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(timestampMilliseconds),
                "Timestamp must be positive.");
        }

        var timestamp = timestampMilliseconds.ToString(CultureInfo.InvariantCulture);
        var signature = BitunixRequestSigner.CreateWebSocketLoginSignature(
            nonce,
            timestamp,
            credentials.ApiKey,
            credentials.SecretKey);
        return JsonSerializer.Serialize(
            new
            {
                op = "login",
                args = new[]
                {
                    new
                    {
                        apiKey = credentials.ApiKey,
                        timestamp = timestampMilliseconds,
                        nonce,
                        sign = signature.Sign
                    }
                }
            });
    }

    public static string CreateSubscriptionMessage(
        IEnumerable<string>? channels = null)
    {
        var normalized = (channels ?? DefaultChannels)
            .Where(channel => !string.IsNullOrWhiteSpace(channel))
            .Select(channel => channel.Trim().ToLowerInvariant())
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
        if (normalized.Length == 0)
        {
            throw new ArgumentException(
                "At least one private channel is required.",
                nameof(channels));
        }

        return JsonSerializer.Serialize(
            new
            {
                op = "subscribe",
                args = normalized.Select(channel => new { ch = channel }).ToArray()
            });
    }

    public static string CreatePingMessage(long unixSeconds)
    {
        if (unixSeconds <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(unixSeconds),
                "Ping timestamp must be positive.");
        }

        return JsonSerializer.Serialize(new { op = "ping", ping = unixSeconds });
    }

    public static void EnsureLoginAccepted(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new BitunixSafeException(
                "Bitunix private WebSocket returned a malformed login response.");
        }

        var code = ReadCode(root);
        if (code.Length > 0 && code != "0")
        {
            throw new BitunixSafeException(ReadSafeMessage(root), code);
        }

        if (root.TryGetProperty("event", out var eventProperty)
            && eventProperty.ValueKind == JsonValueKind.String
            && string.Equals(
                eventProperty.GetString(),
                "error",
                StringComparison.OrdinalIgnoreCase))
        {
            throw new BitunixSafeException(ReadSafeMessage(root));
        }
    }

    public static BitunixPrivateStreamEvent? TryParseEvent(
        JsonElement root,
        DateTimeOffset receivedAt)
    {
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("ch", out var channelProperty)
            || channelProperty.ValueKind != JsonValueKind.String
            || !root.TryGetProperty("data", out var data))
        {
            return null;
        }

        var channel = channelProperty.GetString();
        if (string.IsNullOrWhiteSpace(channel))
        {
            return null;
        }

        var timestamp = ReadInt64(root, "ts");
        var eventType = data.ValueKind == JsonValueKind.Object
            && data.TryGetProperty("event", out var eventProperty)
            && eventProperty.ValueKind == JsonValueKind.String
                ? eventProperty.GetString() ?? string.Empty
                : string.Empty;
        return new BitunixPrivateStreamEvent(
            channel,
            timestamp,
            eventType,
            data.Clone(),
            receivedAt.ToUniversalTime());
    }

    private static string ReadCode(JsonElement root)
    {
        if (!root.TryGetProperty("code", out var code))
        {
            return string.Empty;
        }

        return code.ValueKind == JsonValueKind.String
            ? code.GetString() ?? string.Empty
            : code.GetRawText();
    }

    private static string ReadSafeMessage(JsonElement root)
    {
        if (root.TryGetProperty("msg", out var message)
            && message.ValueKind == JsonValueKind.String)
        {
            var value = message.GetString();
            if (!string.IsNullOrWhiteSpace(value) && value.Length <= 300)
            {
                return value;
            }
        }

        return "Bitunix rejected the private WebSocket login.";
    }

    private static long ReadInt64(JsonElement root, string propertyName)
    {
        if (!root.TryGetProperty(propertyName, out var property))
        {
            return 0;
        }

        if (property.ValueKind == JsonValueKind.Number
            && property.TryGetInt64(out var numeric))
        {
            return numeric;
        }

        return property.ValueKind == JsonValueKind.String
            && long.TryParse(
                property.GetString(),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var parsed)
            ? parsed
            : 0;
    }
}
