using System.Security.Cryptography;
using System.Text;

namespace Quantara.Api.Supervisor;

public sealed record SupervisorSupportSessionRegistrationContract(
    string Token,
    DateTimeOffset ExpiresAtUtc,
    string Scope,
    IReadOnlyList<SupervisorEvidenceContract> Evidence);

public sealed record SupervisorEvidenceUpdateContract(
    IReadOnlyList<SupervisorEvidenceContract> Evidence);

public sealed record SupervisorSupportSessionSnapshotContract(
    string SessionId,
    string TokenFingerprint,
    DateTimeOffset ExpiresAtUtc,
    string Scope,
    int EvidenceCount,
    DateTimeOffset LastUpdatedAtUtc);

public sealed record SupervisorSupportSessionView(
    SupervisorSupportSessionSnapshotContract Snapshot,
    IReadOnlyList<SupervisorEvidenceContract> Evidence);

public sealed class SupervisorSupportSessionRegistry
{
    public const string RequiredScope = "diagnostics.read";
    private const int MaximumActiveSessions = 16;
    private static readonly TimeSpan MaximumSessionLifetime = TimeSpan.FromMinutes(60);

    private readonly object _sync = new();
    private readonly Dictionary<string, SessionEntry> _sessions = new(StringComparer.Ordinal);
    private readonly TimeProvider _timeProvider;

    public SupervisorSupportSessionRegistry(TimeProvider timeProvider)
    {
        _timeProvider = timeProvider;
    }

    public bool TryRegister(
        SupervisorSupportSessionRegistrationContract registration,
        out SupervisorSupportSessionSnapshotContract? snapshot,
        out string error)
    {
        snapshot = null;
        var now = _timeProvider.GetUtcNow();
        if (!ValidToken(registration.Token)
            || !string.Equals(registration.Scope, RequiredScope, StringComparison.Ordinal)
            || registration.ExpiresAtUtc <= now
            || registration.ExpiresAtUtc - now > MaximumSessionLifetime)
        {
            error = "invalid_support_session";
            return false;
        }

        if (!TryValidateEvidence(registration.Evidence, now, out error))
        {
            return false;
        }

        var tokenHash = HashToken(registration.Token);
        var fingerprint = tokenHash[..16];
        lock (_sync)
        {
            PurgeExpiredLocked(now);
            if (!_sessions.ContainsKey(tokenHash) && _sessions.Count >= MaximumActiveSessions)
            {
                error = "support_session_capacity_reached";
                return false;
            }

            var entry = new SessionEntry(
                tokenHash,
                fingerprint,
                registration.ExpiresAtUtc,
                registration.Scope,
                registration.Evidence.ToArray(),
                now);
            _sessions[tokenHash] = entry;
            snapshot = ToSnapshot(entry);
        }

        error = string.Empty;
        return true;
    }

    public bool TryUpdateEvidence(
        string token,
        SupervisorEvidenceUpdateContract update,
        out SupervisorSupportSessionSnapshotContract? snapshot,
        out string error)
    {
        snapshot = null;
        var now = _timeProvider.GetUtcNow();
        if (!TryValidateEvidence(update.Evidence, now, out error))
        {
            return false;
        }

        var tokenHash = ValidToken(token) ? HashToken(token) : string.Empty;
        lock (_sync)
        {
            PurgeExpiredLocked(now);
            if (tokenHash.Length == 0 || !_sessions.TryGetValue(tokenHash, out var entry))
            {
                error = "support_session_not_found";
                return false;
            }

            var updated = entry with
            {
                Evidence = update.Evidence.ToArray(),
                LastUpdatedAtUtc = now
            };
            _sessions[tokenHash] = updated;
            snapshot = ToSnapshot(updated);
        }

        error = string.Empty;
        return true;
    }

    public bool TryGet(string token, out SupervisorSupportSessionView? view)
    {
        view = null;
        if (!ValidToken(token))
        {
            return false;
        }

        var now = _timeProvider.GetUtcNow();
        var tokenHash = HashToken(token);
        lock (_sync)
        {
            PurgeExpiredLocked(now);
            if (!_sessions.TryGetValue(tokenHash, out var entry))
            {
                return false;
            }

            view = new SupervisorSupportSessionView(
                ToSnapshot(entry),
                entry.Evidence.ToArray());
            return true;
        }
    }

    public bool Revoke(string token)
    {
        if (!ValidToken(token))
        {
            return false;
        }

        lock (_sync)
        {
            return _sessions.Remove(HashToken(token));
        }
    }

    private static bool TryValidateEvidence(
        IReadOnlyList<SupervisorEvidenceContract>? evidence,
        DateTimeOffset now,
        out string error)
    {
        if (evidence is null)
        {
            error = "evidence_required";
            return false;
        }

        var validationRequest = new SupervisorAnalysisRequestContract(
            "support-session-ingest",
            now,
            evidence,
            null);
        return SupervisorEvidenceValidator.TryValidate(validationRequest, out error);
    }

    private static bool ValidToken(string? token) =>
        !string.IsNullOrWhiteSpace(token) && token.Length is >= 32 and <= 256;

    private static string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)))
            .ToLowerInvariant();

    private void PurgeExpiredLocked(DateTimeOffset now)
    {
        foreach (var key in _sessions
                     .Where(pair => pair.Value.ExpiresAtUtc <= now)
                     .Select(pair => pair.Key)
                     .ToArray())
        {
            _sessions.Remove(key);
        }
    }

    private static SupervisorSupportSessionSnapshotContract ToSnapshot(SessionEntry entry) =>
        new(
            $"support-{entry.TokenFingerprint}",
            entry.TokenFingerprint,
            entry.ExpiresAtUtc,
            entry.Scope,
            entry.Evidence.Count,
            entry.LastUpdatedAtUtc);

    private sealed record SessionEntry(
        string TokenHash,
        string TokenFingerprint,
        DateTimeOffset ExpiresAtUtc,
        string Scope,
        IReadOnlyList<SupervisorEvidenceContract> Evidence,
        DateTimeOffset LastUpdatedAtUtc);
}
