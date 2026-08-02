using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Quantara.Infrastructure.Exchanges.Bitunix;

public sealed record BitunixCredentials(string ApiKey, string SecretKey)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(ApiKey) || ApiKey.Length < 8)
        {
            throw new ArgumentException("Bitunix API key is incomplete.", nameof(ApiKey));
        }

        if (string.IsNullOrWhiteSpace(SecretKey) || SecretKey.Length < 8)
        {
            throw new ArgumentException("Bitunix secret key is incomplete.", nameof(SecretKey));
        }
    }

    public string MaskedApiKey => ApiKey.Length <= 8
        ? "********"
        : $"{ApiKey[..4]}****{ApiKey[^4..]}";
}

public sealed record BitunixPlaceOrderRequest(
    string Symbol,
    decimal Quantity,
    string Side,
    string TradeSide,
    string OrderType,
    string ClientId,
    bool ReduceOnly,
    decimal? Price,
    string? Effect,
    decimal? TakeProfitPrice,
    decimal? StopLossPrice);

public sealed record BitunixPlacedOrder(string OrderId, string ClientId);

public sealed class BitunixSafeException : Exception
{
    public BitunixSafeException(string message, object? code = null)
        : base(message)
    {
        Code = code;
    }

    public object? Code { get; }
}

public sealed class BitunixLiveRestClient
{
    private static readonly Uri DefaultBaseAddress = new("https://fapi.bitunix.com");
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    private readonly HttpClient _httpClient;
    private readonly TimeProvider _timeProvider;

    public BitunixLiveRestClient(HttpClient httpClient, TimeProvider timeProvider)
    {
        _httpClient = httpClient;
        _timeProvider = timeProvider;
        _httpClient.BaseAddress ??= DefaultBaseAddress;
        _httpClient.DefaultRequestHeaders.Accept.Clear();
        _httpClient.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/json"));
    }

    public Task<JsonElement> GetAccountAsync(
        BitunixCredentials credentials,
        CancellationToken cancellationToken) =>
        SendSignedAsync(
            HttpMethod.Get,
            "/api/v1/futures/account",
            Query(("marginCoin", "USDT")),
            null,
            credentials,
            cancellationToken);

    public Task<JsonElement> GetPendingPositionsAsync(
        BitunixCredentials credentials,
        CancellationToken cancellationToken) =>
        SendSignedAsync(
            HttpMethod.Get,
            "/api/v1/futures/position/get_pending_positions",
            null,
            null,
            credentials,
            cancellationToken);

    public Task<JsonElement> GetPendingOrdersAsync(
        BitunixCredentials credentials,
        CancellationToken cancellationToken) =>
        SendSignedAsync(
            HttpMethod.Get,
            "/api/v1/futures/trade/get_pending_orders",
            Query(("limit", "100")),
            null,
            credentials,
            cancellationToken);

    public Task<JsonElement> GetLeverageAndMarginModeAsync(
        string symbol,
        BitunixCredentials credentials,
        CancellationToken cancellationToken) =>
        SendSignedAsync(
            HttpMethod.Get,
            "/api/v1/futures/account/get_leverage_margin_mode",
            Query(("marginCoin", "USDT"), ("symbol", NormalizeSymbol(symbol))),
            null,
            credentials,
            cancellationToken);

    public async Task ChangeMarginModeToIsolatedAsync(
        string symbol,
        BitunixCredentials credentials,
        CancellationToken cancellationToken)
    {
        var body = Body(
            ("marginCoin", "USDT"),
            ("marginMode", "ISOLATION"),
            ("symbol", NormalizeSymbol(symbol)));
        _ = await SendSignedAsync(
                HttpMethod.Post,
                "/api/v1/futures/account/change_margin_mode",
                null,
                body,
                credentials,
                cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task ChangeLeverageAsync(
        string symbol,
        int leverage,
        BitunixCredentials credentials,
        CancellationToken cancellationToken)
    {
        if (leverage is < 1 or > 125)
        {
            throw new ArgumentOutOfRangeException(
                nameof(leverage),
                "Leverage must be between 1 and 125.");
        }

        var body = Body(
            ("leverage", leverage),
            ("marginCoin", "USDT"),
            ("symbol", NormalizeSymbol(symbol)));
        _ = await SendSignedAsync(
                HttpMethod.Post,
                "/api/v1/futures/account/change_leverage",
                null,
                body,
                credentials,
                cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<BitunixPlacedOrder> PlaceOrderAsync(
        BitunixPlaceOrderRequest request,
        BitunixCredentials credentials,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        ValidateOrder(request);
        var body = Body(
            ("clientId", request.ClientId.Trim()),
            ("orderType", request.OrderType.Trim().ToUpperInvariant()),
            ("qty", FormatDecimal(request.Quantity)),
            ("reduceOnly", request.ReduceOnly),
            ("side", request.Side.Trim().ToUpperInvariant()),
            ("symbol", NormalizeSymbol(request.Symbol)),
            ("tradeSide", request.TradeSide.Trim().ToUpperInvariant()));
        AddOptional(body, "effect", request.Effect?.Trim().ToUpperInvariant());
        AddOptional(body, "price", request.Price);
        AddProtection(body, "tp", request.TakeProfitPrice);
        AddProtection(body, "sl", request.StopLossPrice);

        var data = await SendSignedAsync(
                HttpMethod.Post,
                "/api/v1/futures/trade/place_order",
                null,
                body,
                credentials,
                cancellationToken)
            .ConfigureAwait(false);
        return new BitunixPlacedOrder(
            GetRequiredString(data, "orderId"),
            GetRequiredString(data, "clientId"));
    }

    internal async Task<JsonElement> SendSignedAsync(
        HttpMethod method,
        string path,
        IReadOnlyDictionary<string, string>? query,
        object? body,
        BitunixCredentials credentials,
        CancellationToken cancellationToken)
    {
        credentials.Validate();
        if (string.IsNullOrWhiteSpace(path) || path[0] != '/')
        {
            throw new ArgumentException("A root-relative API path is required.", nameof(path));
        }

        var sortedQuery = CopySortedQuery(query);
        var compactBody = body is null
            ? string.Empty
            : JsonSerializer.Serialize(body, JsonOptions);
        var nonce = CreateNonce();
        var timestamp = _timeProvider
            .GetUtcNow()
            .ToUnixTimeMilliseconds()
            .ToString(CultureInfo.InvariantCulture);
        var signature = BitunixRequestSigner.CreateRestSignature(
            nonce,
            timestamp,
            credentials.ApiKey,
            credentials.SecretKey,
            sortedQuery,
            compactBody);

        using var request = new HttpRequestMessage(method, BuildUri(path, sortedQuery));
        request.Headers.TryAddWithoutValidation("api-key", credentials.ApiKey);
        request.Headers.TryAddWithoutValidation("nonce", nonce);
        request.Headers.TryAddWithoutValidation("timestamp", timestamp);
        request.Headers.TryAddWithoutValidation("sign", signature.Sign);
        request.Headers.TryAddWithoutValidation("language", "en-US");
        if (body is not null)
        {
            request.Content = new StringContent(compactBody, Encoding.UTF8, "application/json");
        }

        using var response = await _httpClient
            .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);
        var content = await response.Content
            .ReadAsStringAsync(cancellationToken)
            .ConfigureAwait(false);
        if (content.Length > 2_000_000)
        {
            throw new BitunixSafeException("Bitunix returned an oversized response.");
        }

        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(content);
        }
        catch (JsonException)
        {
            throw new BitunixSafeException(
                "Bitunix returned an unreadable response.",
                (int)response.StatusCode);
        }

        using (document)
        {
            var root = document.RootElement;
            var code = ReadCode(root);
            if (!response.IsSuccessStatusCode || code != "0")
            {
                throw new BitunixSafeException(
                    ReadSafeMessage(root),
                    code.Length == 0 ? (int)response.StatusCode : code);
            }

            return root.TryGetProperty("data", out var data)
                ? data.Clone()
                : default;
        }
    }

    private Uri BuildUri(
        string path,
        IReadOnlyDictionary<string, string>? query)
    {
        var builder = new UriBuilder(new Uri(_httpClient.BaseAddress!, path));
        if (query is not null && query.Count > 0)
        {
            builder.Query = string.Join(
                "&",
                query.Select(pair =>
                    $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"));
        }

        return builder.Uri;
    }

    private static SortedDictionary<string, string>? CopySortedQuery(
        IReadOnlyDictionary<string, string>? query)
    {
        if (query is null)
        {
            return null;
        }

        var sorted = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var pair in query)
        {
            sorted[pair.Key] = pair.Value;
        }

        return sorted;
    }

    private static SortedDictionary<string, string> Query(
        params (string Key, string Value)[] values)
    {
        var query = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var value in values)
        {
            query[value.Key] = value.Value;
        }

        return query;
    }

    private static SortedDictionary<string, object?> Body(
        params (string Key, object? Value)[] values)
    {
        var body = new SortedDictionary<string, object?>(StringComparer.Ordinal);
        foreach (var value in values)
        {
            body[value.Key] = value.Value;
        }

        return body;
    }

    private static void ValidateOrder(BitunixPlaceOrderRequest request)
    {
        _ = NormalizeSymbol(request.Symbol);
        if (request.Quantity <= 0m)
        {
            throw new ArgumentException(
                "Order quantity must be positive.",
                nameof(request));
        }

        if (string.IsNullOrWhiteSpace(request.ClientId)
            || request.ClientId.Trim().Length > 64)
        {
            throw new ArgumentException(
                "Client ID is required and must be at most 64 characters.",
                nameof(request));
        }

        if (string.Equals(request.OrderType, "LIMIT", StringComparison.OrdinalIgnoreCase)
            && request.Price is null)
        {
            throw new ArgumentException(
                "Limit orders require a price.",
                nameof(request));
        }
    }

    private static string NormalizeSymbol(string symbol)
    {
        if (string.IsNullOrWhiteSpace(symbol))
        {
            throw new ArgumentException("Symbol is required.", nameof(symbol));
        }

        var normalized = symbol.Trim().ToUpperInvariant();
        if (normalized.Length is < 5 or > 32
            || normalized.Any(character => !char.IsAsciiLetterOrDigit(character)))
        {
            throw new ArgumentException("Symbol contains invalid characters.", nameof(symbol));
        }

        return normalized;
    }

    private static string FormatDecimal(decimal value) =>
        value.ToString("0.############################", CultureInfo.InvariantCulture);

    private static void AddOptional(
        IDictionary<string, object?> body,
        string key,
        string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            body[key] = value;
        }
    }

    private static void AddOptional(
        IDictionary<string, object?> body,
        string key,
        decimal? value)
    {
        if (value is not null)
        {
            body[key] = FormatDecimal(value.Value);
        }
    }

    private static void AddProtection(
        IDictionary<string, object?> body,
        string prefix,
        decimal? price)
    {
        if (price is null)
        {
            return;
        }

        body[$"{prefix}OrderType"] = "MARKET";
        body[$"{prefix}Price"] = FormatDecimal(price.Value);
        body[$"{prefix}StopType"] = "MARK_PRICE";
    }

    private static string GetRequiredString(JsonElement element, string propertyName)
    {
        if (element.ValueKind == JsonValueKind.Object
            && element.TryGetProperty(propertyName, out var property))
        {
            var value = property.ValueKind == JsonValueKind.String
                ? property.GetString()
                : property.GetRawText();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        throw new BitunixSafeException(
            $"Bitunix response did not contain {propertyName}.");
    }

    private static string ReadCode(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("code", out var code))
        {
            return string.Empty;
        }

        return code.ValueKind == JsonValueKind.String
            ? code.GetString() ?? string.Empty
            : code.GetRawText();
    }

    private static string ReadSafeMessage(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Object
            && root.TryGetProperty("msg", out var message)
            && message.ValueKind == JsonValueKind.String)
        {
            var value = message.GetString();
            if (!string.IsNullOrWhiteSpace(value) && value.Length <= 300)
            {
                return value;
            }
        }

        return "Bitunix rejected the request.";
    }

    private static string CreateNonce() =>
        string.Concat(
            RandomNumberGenerator
                .GetBytes(16)
                .Select(value => value.ToString("x2", CultureInfo.InvariantCulture)));
}
