using System.Text.RegularExpressions;

namespace Quantara.Api.Supervisor;

public static partial class SupervisorEvidenceValidator
{
    private const int MaximumEvidenceCount = 500;
    private const int MaximumAttributeCount = 64;
    private const int MaximumTextLength = 32_000;

    private static readonly HashSet<string> AllowedDomains = new(
        [
            "app",
            "backend",
            "runtime",
            "strategy",
            "risk",
            "journal",
            "build",
            "test",
            "config",
            "persistence"
        ],
        StringComparer.Ordinal);

    private static readonly string[] SecretKeyFragments =
    [
        "apikey",
        "apisecret",
        "secretkey",
        "authorization",
        "accesstoken",
        "refreshtoken",
        "sessiontoken",
        "password",
        "privatekey",
        "signature",
        "credential"
    ];

    public static bool TryValidate(
        SupervisorAnalysisRequestContract? request,
        out string error)
    {
        if (request is null)
        {
            error = "request_required";
            return false;
        }

        if (!ValidText(request.BundleId, 128) || request.Evidence is null)
        {
            error = "invalid_bundle";
            return false;
        }

        if (request.Evidence.Count is < 1 or > MaximumEvidenceCount)
        {
            error = "invalid_evidence_count";
            return false;
        }

        if (request.ReviewGoal is { Length: > MaximumTextLength })
        {
            error = "review_goal_too_large";
            return false;
        }

        foreach (var item in request.Evidence)
        {
            if (!TryValidateEvidence(item, out error))
            {
                return false;
            }
        }

        error = string.Empty;
        return true;
    }

    private static bool TryValidateEvidence(
        SupervisorEvidenceContract item,
        out string error)
    {
        if (!ValidText(item.EvidenceId, 256)
            || !AllowedDomains.Contains(item.Domain)
            || !ValidText(item.Kind, 128)
            || !ValidText(item.Summary, MaximumTextLength)
            || !ValidText(item.Severity, 32))
        {
            error = "invalid_evidence_shape";
            return false;
        }

        if (ContainsRawCredential(item.EvidenceId)
            || ContainsRawCredential(item.Kind)
            || ContainsRawCredential(item.Summary)
            || ContainsRawCredential(item.Component)
            || ContainsRawCredential(item.Version)
            || ContainsRawCredential(item.CorrelationId))
        {
            error = "credential_like_evidence_rejected";
            return false;
        }

        var attributes = item.Attributes ?? SupervisorContractCollections.EmptyAttributes;
        if (attributes.Count > MaximumAttributeCount)
        {
            error = "too_many_evidence_attributes";
            return false;
        }

        foreach (var pair in attributes)
        {
            if (!ValidText(pair.Key, 128) || pair.Value.Length > MaximumTextLength)
            {
                error = "invalid_evidence_attribute";
                return false;
            }

            if (IsSecretKey(pair.Key) || ContainsRawCredential(pair.Value))
            {
                error = "credential_like_evidence_rejected";
                return false;
            }
        }

        error = string.Empty;
        return true;
    }

    private static bool ValidText(string? value, int maxLength) =>
        !string.IsNullOrWhiteSpace(value) && value.Length <= maxLength;

    private static bool IsSecretKey(string key)
    {
        var normalized = new string(
            key.Where(char.IsLetterOrDigit)
                .Select(char.ToLowerInvariant)
                .ToArray());
        return SecretKeyFragments.Any(normalized.Contains);
    }

    private static bool ContainsRawCredential(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        return AuthorizationCredentialRegex().IsMatch(value)
            || CredentialAssignmentRegex().IsMatch(value);
    }

    [GeneratedRegex(
        @"(?i)\b(?:bearer|basic)\s+(?!\[?REDACTED)[A-Za-z0-9._~+/=-]{8,}",
        RegexOptions.CultureInvariant)]
    private static partial Regex AuthorizationCredentialRegex();

    [GeneratedRegex(
        "(?i)\\b(?:api[_-]?(?:key|secret)|secret[_-]?key|access[_-]?token|refresh[_-]?token|session[_-]?token|password|private[_-]?key|signature|authorization)\\s*[:=]\\s*[\\\"']?(?!\\[?REDACTED)[^\\s,;}\\\"']{4,}",
        RegexOptions.CultureInvariant)]
    private static partial Regex CredentialAssignmentRegex();
}
