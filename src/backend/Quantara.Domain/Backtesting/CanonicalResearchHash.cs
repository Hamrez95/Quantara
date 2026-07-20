using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Quantara.Domain.Backtesting;

internal static class CanonicalResearchHash
{
    public static string Compute(Action<StringBuilder> writeCanonicalContent)
    {
        ArgumentNullException.ThrowIfNull(writeCanonicalContent);

        var builder = new StringBuilder();
        writeCanonicalContent(builder);
        var bytes = Encoding.UTF8.GetBytes(builder.ToString());
        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }

    public static void Append(StringBuilder builder, string value)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentNullException.ThrowIfNull(value);

        builder.Append(value.Length.ToString(CultureInfo.InvariantCulture));
        builder.Append(':');
        builder.Append(value);
        builder.Append('\n');
    }

    public static void Append(StringBuilder builder, int value)
    {
        Append(builder, value.ToString(CultureInfo.InvariantCulture));
    }

    public static void Append(StringBuilder builder, long value)
    {
        Append(builder, value.ToString(CultureInfo.InvariantCulture));
    }

    public static void Append(StringBuilder builder, decimal value)
    {
        Append(builder, value.ToString("G29", CultureInfo.InvariantCulture));
    }

    public static void Append(StringBuilder builder, DateTimeOffset value)
    {
        Append(builder, value.ToUniversalTime().Ticks);
    }

    public static void Append(StringBuilder builder, TimeSpan value)
    {
        Append(builder, value.Ticks);
    }

    public static bool IsSha256(string value)
    {
        return value.Length == 64 && value.All(IsLowerHexCharacter);
    }

    public static bool IsGitCommitSha(string value)
    {
        return value.Length is 40 or 64 && value.All(IsHexCharacter);
    }

    private static bool IsLowerHexCharacter(char value)
    {
        return value is >= '0' and <= '9' or >= 'a' and <= 'f';
    }

    private static bool IsHexCharacter(char value)
    {
        return value is >= '0' and <= '9'
            or >= 'a' and <= 'f'
            or >= 'A' and <= 'F';
    }
}
