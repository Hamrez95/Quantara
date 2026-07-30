using System.Security.Cryptography;
using System.Text;

namespace Quantara.Infrastructure.Exchanges.Bitunix;

public sealed record BitunixSignature(string Digest, string Sign);

public static class BitunixRequestSigner
{
    public static BitunixSignature CreateRestSignature(
        string nonce,
        string timestamp,
        string apiKey,
        string secretKey,
        IReadOnlyDictionary<string, string>? queryParameters = null,
        string? compactBody = null)
    {
        ValidateSecrets(nonce, timestamp, apiKey, secretKey);
        var query = CanonicalizeQuery(queryParameters);
        var body = compactBody ?? string.Empty;
        var digest = Sha256Hex($"{nonce}{timestamp}{apiKey}{query}{body}");
        return new BitunixSignature(digest, Sha256Hex($"{digest}{secretKey}"));
    }

    public static BitunixSignature CreateWebSocketSignature(
        string nonce,
        string timestamp,
        string apiKey,
        string secretKey,
        IReadOnlyDictionary<string, string>? additionalParameters = null)
    {
        ValidateSecrets(nonce, timestamp, apiKey, secretKey);
        var parameters = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["apiKey"] = apiKey,
            ["nonce"] = nonce,
            ["timestamp"] = timestamp
        };
        if (additionalParameters is not null)
        {
            foreach (var pair in additionalParameters)
            {
                if (string.Equals(pair.Key, "sign", StringComparison.Ordinal))
                {
                    continue;
                }

                parameters[pair.Key] = pair.Value;
            }
        }

        var canonical = string.Concat(parameters.Select(pair => pair.Key + pair.Value));
        var digest = Sha256Hex($"{nonce}{timestamp}{apiKey}{canonical}");
        return new BitunixSignature(digest, Sha256Hex($"{digest}{secretKey}"));
    }

    public static string CanonicalizeQuery(
        IReadOnlyDictionary<string, string>? queryParameters)
    {
        if (queryParameters is null || queryParameters.Count == 0)
        {
            return string.Empty;
        }

        return string.Concat(
            queryParameters
                .OrderBy(pair => pair.Key, StringComparer.Ordinal)
                .Select(pair => pair.Key + pair.Value));
    }

    private static string Sha256Hex(string input) =>
        Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(input)))
            .ToLowerInvariant();

    private static void ValidateSecrets(
        string nonce,
        string timestamp,
        string apiKey,
        string secretKey)
    {
        if (string.IsNullOrWhiteSpace(nonce))
        {
            throw new ArgumentException("Nonce is required.", nameof(nonce));
        }

        if (string.IsNullOrWhiteSpace(timestamp))
        {
            throw new ArgumentException("Timestamp is required.", nameof(timestamp));
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new ArgumentException("API key is required.", nameof(apiKey));
        }

        if (string.IsNullOrWhiteSpace(secretKey))
        {
            throw new ArgumentException("Secret key is required.", nameof(secretKey));
        }
    }
}
