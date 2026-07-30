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
    public void WebSocketSignatureSortsParametersAndExcludesSign()
    {
        var signature = BitunixRequestSigner.CreateWebSocketSignature(
            "123456",
            "1724285700000",
            "9a25209b66004da404d9ddcb48d1e11f",
            "secret",
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["symbol"] = "BTC",
                ["sign"] = "must-not-be-signed"
            });

        Assert.Equal(
            "493a2e724afc59e0f1cf911b40c3a12fa520bb0abd950b3409142de72e31313f",
            signature.Digest);
        Assert.Equal(
            "c1171b1ed0d500ce3dcaa0f9996a3c9677e8681df18f4fa23857101c4bb97eb8",
            signature.Sign);
    }
}
