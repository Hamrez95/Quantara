using System.Net;
using System.Text;
using Quantara.Infrastructure.Exchanges.Bitunix;

namespace Quantara.Domain.Tests;

public sealed class BitunixLiveRestClientTests
{
    [Fact]
    public async Task PlaceOrderUsesExactBodySignatureAndProtectionFields()
    {
        var handler = new CapturingHandler(
            HttpStatusCode.OK,
            "{\"code\":0,\"msg\":\"Success\",\"data\":{\"orderId\":\"123\",\"clientId\":\"q-test-1\"}}");
        using var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://fapi.bitunix.com")
        };
        var client = new BitunixLiveRestClient(httpClient, new FixedTimeProvider());
        var credentials = new BitunixCredentials("api-key-12345678", "secret-key-12345678");

        var result = await client.PlaceOrderAsync(
            new BitunixPlaceOrderRequest(
                "btcusdt",
                0.125m,
                "buy",
                "open",
                "market",
                "q-test-1",
                false,
                null,
                null,
                65000m,
                62000m),
            credentials,
            CancellationToken.None);

        Assert.Equal("123", result.OrderId);
        Assert.Equal("q-test-1", result.ClientId);
        Assert.NotNull(handler.LastRequest);
        Assert.Equal(HttpMethod.Post, handler.LastRequest.Method);
        Assert.Equal(
            "/api/v1/futures/trade/place_order",
            handler.LastRequest.RequestUri?.AbsolutePath);
        Assert.Contains("\"symbol\":\"BTCUSDT\"", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("\"qty\":\"0.125\"", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("\"slPrice\":\"62000\"", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("\"tpPrice\":\"65000\"", handler.LastBody, StringComparison.Ordinal);

        var nonce = RequiredHeader(handler.LastRequest, "nonce");
        var timestamp = RequiredHeader(handler.LastRequest, "timestamp");
        var sentSign = RequiredHeader(handler.LastRequest, "sign");
        var expected = BitunixRequestSigner.CreateRestSignature(
            nonce,
            timestamp,
            credentials.ApiKey,
            credentials.SecretKey,
            null,
            handler.LastBody);
        Assert.Equal(expected.Sign, sentSign);
    }

    [Fact]
    public async Task AccountQueryIsSortedAndSignedFromSameCanonicalQuery()
    {
        var handler = new CapturingHandler(
            HttpStatusCode.OK,
            "{\"code\":0,\"msg\":\"Success\",\"data\":{\"available\":\"800\"}}");
        using var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://fapi.bitunix.com")
        };
        var client = new BitunixLiveRestClient(httpClient, new FixedTimeProvider());
        var credentials = new BitunixCredentials("api-key-12345678", "secret-key-12345678");

        var data = await client.GetAccountAsync(credentials, CancellationToken.None);

        Assert.Equal("800", data.GetProperty("available").GetString());
        Assert.Equal("?marginCoin=USDT", handler.LastRequest?.RequestUri?.Query);
        var nonce = RequiredHeader(handler.LastRequest!, "nonce");
        var timestamp = RequiredHeader(handler.LastRequest!, "timestamp");
        var expected = BitunixRequestSigner.CreateRestSignature(
            nonce,
            timestamp,
            credentials.ApiKey,
            credentials.SecretKey,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["marginCoin"] = "USDT"
            });
        Assert.Equal(expected.Sign, RequiredHeader(handler.LastRequest!, "sign"));
    }

    [Fact]
    public async Task RejectedExchangeResponseThrowsSafeExceptionWithoutSecrets()
    {
        var handler = new CapturingHandler(
            HttpStatusCode.OK,
            "{\"code\":10007,\"msg\":\"Invalid signature\",\"data\":null}");
        using var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://fapi.bitunix.com")
        };
        var client = new BitunixLiveRestClient(httpClient, new FixedTimeProvider());
        var credentials = new BitunixCredentials("api-key-12345678", "secret-key-12345678");

        var exception = await Assert.ThrowsAsync<BitunixSafeException>(
            () => client.GetPendingOrdersAsync(credentials, CancellationToken.None));

        Assert.Equal("Invalid signature", exception.Message);
        Assert.DoesNotContain(credentials.ApiKey, exception.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(credentials.SecretKey, exception.ToString(), StringComparison.Ordinal);
    }

    private static string RequiredHeader(HttpRequestMessage request, string name)
    {
        Assert.True(request.Headers.TryGetValues(name, out var values));
        return Assert.Single(values);
    }

    private sealed class CapturingHandler(HttpStatusCode statusCode, string responseBody)
        : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }

        public string LastBody { get; private set; } = string.Empty;

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            LastRequest = request;
            LastBody = request.Content is null
                ? string.Empty
                : await request.Content
                    .ReadAsStringAsync(cancellationToken)
                    .ConfigureAwait(false);
            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json")
            };
        }
    }

    private sealed class FixedTimeProvider : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() =>
            new(2026, 7, 30, 13, 30, 0, TimeSpan.Zero);
    }
}
