using Quantara.Infrastructure.Exchanges.Bitunix;

namespace Quantara.Domain.Tests;

public sealed class BitunixRequestSignerTests
{
    [Fact]
    public void RestSignatureMatchesOfficialCanonicalExample()
    {
        var signature = BitunixRequestSigner.CreateRestSignature(
            "123456",
            "20241120123045",
            "yourApiKey",
            "yourSecretKey",
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["uid"] = "200",
                ["id"] = "1"
            },
            "{\"uid\":\"2899\",\"arr\":[{\"id\":1,\"name\":\"maple\"},{\"id\":2,\"name\":\"lily\"}]}");

        Assert.Equal(
            "75099831ac6803e9c5b79dd3cde2c3c529b4750bd3508186afdde0dd13599b38",
            signature.Digest);
        Assert.Equal(
            "00397cd1e52c7dce3258067324363b6361fabc9178a0912b330c138db8745655",
            signature.Sign);
    }

    [Fact]
    public void RestQueryIsSortedByAsciiKeyWithoutSeparators()
    {
        var query = BitunixRequestSigner.CanonicalizeQuery(
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["symbol"] = "BTCUSDT",
                ["marginCoin"] = "USDT",
                ["limit"] = "100"
            });

        Assert.Equal("limit100marginCoinUSDTsymbolBTCUSDT", query);
    }

    [Fact]
    public void FuturesWebSocketLoginUsesNonceTimestampAndApiKeyOnly()
    {
        var signature = BitunixRequestSigner.CreateWebSocketLoginSignature(
            "123456",
            "1724285700000",
            "9a25209b66004da404d9ddcb48d1e11f",
            "secret");

        Assert.Equal(
            "fd2f7092a756fd96c95f17fc04dde64f6d68785769afeda2812d46d7151d237e",
            signature.Digest);
        Assert.Equal(
            "b0936739fe4863f5dc5ab53ce77ab3c3f75ff739b2587531e4852a82e2641a65",
            signature.Sign);
    }
}
