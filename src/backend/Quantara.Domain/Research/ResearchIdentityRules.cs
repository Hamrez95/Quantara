namespace Quantara.Domain.Research;

internal static class ResearchIdentityRules
{
    public static bool IsSemanticVersion(string? value)
    {
        if (!IsValidText(value, 64))
        {
            return false;
        }

        var components = value!.Split('.', StringSplitOptions.None);
        return components.Length == 3
            && components.All(component =>
                component.Length > 0
                && component.All(char.IsAsciiDigit)
                && (component.Length == 1 || component[0] != '0'));
    }

    public static bool IsKebabIdentifier(string? value)
    {
        if (!IsValidText(value, 128)
            || value![0] == '-'
            || value[^1] == '-')
        {
            return false;
        }

        var previousWasSeparator = false;
        foreach (var character in value)
        {
            if (character == '-')
            {
                if (previousWasSeparator)
                {
                    return false;
                }

                previousWasSeparator = true;
                continue;
            }

            if (!char.IsAsciiLetterLower(character)
                && !char.IsAsciiDigit(character))
            {
                return false;
            }

            previousWasSeparator = false;
        }

        return true;
    }

    public static bool IsSha256(string? value)
    {
        return value is not null
            && value.Length == 64
            && value.All(character =>
                char.IsAsciiDigit(character)
                || character is >= 'a' and <= 'f');
    }

    public static bool IsValidText(string? value, int maximumLength)
    {
        return !string.IsNullOrWhiteSpace(value)
            && value.Length <= maximumLength
            && string.Equals(value, value.Trim(), StringComparison.Ordinal);
    }

    public static bool IsSecureHttpsUri(Uri? uri)
    {
        return uri is not null
            && uri.IsAbsoluteUri
            && string.Equals(
                uri.Scheme,
                Uri.UriSchemeHttps,
                StringComparison.OrdinalIgnoreCase)
            && string.IsNullOrEmpty(uri.UserInfo);
    }
}
