using System.Text.Json;
using Quantara.Infrastructure.Exchanges.Bitunix;

namespace Quantara.Domain.Tests;

public sealed class BitunixPrivateWebSocketProtocolTests
{
    [Fact]
    public void LoginMessageUsesOfficialFuturesSignatureAndNeverIncludesSecret()
    {
        var credentials = new BitunixCredentials(
            "9a25209b66004da404d9ddcb48d1e11f",
            "secret-123");

        var message = BitunixPrivateWebSocketProtocol.CreateLoginMessage(
            credentials,
            "123456",
            1724285700000);
        using var document = JsonDocument.Parse(message);
        var argument = document.RootElement.GetProperty("args")[0];

        Assert.Equal("login", document.RootElement.GetProperty("op").GetString());
        Assert.Equal(credentials.ApiKey, argument.GetProperty("apiKey").GetString());
        Assert.Equal(1724285700000, argument.GetProperty("timestamp").GetInt64());
        Assert.Equal("123456", argument.GetProperty("nonce").GetString());
        Assert.Equal(
            "f420c2c520ba97572e512a7b460773dd1afa2a8b3ff92e734e62753f5feb0a57",
            argument.GetProperty("sign").GetString());
        Assert.DoesNotContain(credentials.SecretKey, message, StringComparison.Ordinal);
    }

    [Fact]
    public void SubscriptionMessageNormalizesAndDeduplicatesPrivateChannels()
    {
        var message = BitunixPrivateWebSocketProtocol.CreateSubscriptionMessage(
            ["Position", "order", "position", "balance"]);
        using var document = JsonDocument.Parse(message);
        var channels = document.RootElement
            .GetProperty("args")
            .EnumerateArray()
            .Select(value => value.GetProperty("ch").GetString())
            .ToArray();

        Assert.Collection(
            channels,
            value => Assert.Equal("balance", value),
            value => Assert.Equal("order", value),
            value => Assert.Equal("position", value));
    }

    [Fact]
    public void StreamEventParserClonesPrivateOrderData()
    {
        BitunixPrivateStreamEvent? parsed;
        using (var document = JsonDocument.Parse(
                   "{\"ch\":\"order\",\"ts\":1775541412718,\"data\":{\"event\":\"UPDATE\",\"orderId\":\"123\",\"clientId\":\"q-1\",\"orderStatus\":\"FILLED\"}}"))
        {
            parsed = BitunixPrivateWebSocketProtocol.TryParseEvent(
                document.RootElement,
                new DateTimeOffset(2026, 7, 30, 14, 0, 0, TimeSpan.Zero));
        }

        Assert.NotNull(parsed);
        Assert.Equal("order", parsed.Channel);
        Assert.Equal("UPDATE", parsed.EventType);
        Assert.Equal("123", parsed.Data.GetProperty("orderId").GetString());
        Assert.Equal("FILLED", parsed.Data.GetProperty("orderStatus").GetString());
    }

    [Fact]
    public void LoginErrorFailsClosedWithSafeMessage()
    {
        using var document = JsonDocument.Parse(
            "{\"op\":\"login\",\"code\":10007,\"msg\":\"Invalid signature\"}");

        var exception = Assert.Throws<BitunixSafeException>(
            () => BitunixPrivateWebSocketProtocol.EnsureLoginAccepted(document.RootElement));

        Assert.Equal("Invalid signature", exception.Message);
        Assert.Equal("10007", exception.Code);
    }
}
