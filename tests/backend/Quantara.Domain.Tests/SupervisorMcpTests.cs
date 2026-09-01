using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorMcpTests
{
    private const string Token = "temporary-support-session-token-0123456789abcdef";

    [Fact]
    public void SupportSessionStoresOnlyFingerprintAndExpiresFailClosed()
    {
        var time = new MutableTimeProvider(
            new DateTimeOffset(2026, 8, 14, 9, 30, 0, TimeSpan.Zero));
        var registry = new SupervisorSupportSessionRegistry(time);
        var registration = Registration(time.GetUtcNow().AddMinutes(30));

        Assert.True(registry.TryRegister(registration, out var snapshot, out var error));
        Assert.Equal(string.Empty, error);
        Assert.NotNull(snapshot);
        Assert.DoesNotContain(Token, snapshot!.ToString(), StringComparison.Ordinal);
        Assert.Equal(SupervisorSupportSessionRegistry.RequiredScope, snapshot.Scope);
        Assert.Equal(1, snapshot.EvidenceCount);
        Assert.True(registry.TryGet(Token, out var view));
        Assert.Single(view!.Evidence);

        time.Advance(TimeSpan.FromMinutes(31));
        Assert.False(registry.TryGet(Token, out _));
    }

    [Fact]
    public void SupportSessionRevokeImmediatelyRemovesReadAccess()
    {
        var time = new MutableTimeProvider(
            new DateTimeOffset(2026, 8, 14, 9, 30, 0, TimeSpan.Zero));
        var registry = new SupervisorSupportSessionRegistry(time);
        Assert.True(registry.TryRegister(
            Registration(time.GetUtcNow().AddMinutes(30)),
            out _,
            out _));

        Assert.True(registry.Revoke(Token));
        Assert.False(registry.TryGet(Token, out _));
    }

    [Fact]
    public void SupportSessionRejectsOversizedLifetimeAndRawSecrets()
    {
        var time = new MutableTimeProvider(
            new DateTimeOffset(2026, 8, 14, 9, 30, 0, TimeSpan.Zero));
        var registry = new SupervisorSupportSessionRegistry(time);

        Assert.False(registry.TryRegister(
            Registration(time.GetUtcNow().AddMinutes(61)),
            out _,
            out var ttlError));
        Assert.Equal("invalid_support_session", ttlError);

        var secretRegistration = new SupervisorSupportSessionRegistrationContract(
            Token,
            time.GetUtcNow().AddMinutes(30),
            SupervisorSupportSessionRegistry.RequiredScope,
            [Evidence(summary: "Authorization: Bearer raw-secret-token-123456")]);
        Assert.False(registry.TryRegister(
            secretRegistration,
            out _,
            out var secretError));
        Assert.Equal("credential_like_evidence_rejected", secretError);
    }

    [Fact]
    public void SupervisorHealthAuthorityUsesCanonicalControlToken()
    {
        const string canonicalToken = "canonical-control-token-0123456789abcdef";
        const string legacyToken = "legacy-supervisor-token-0123456789abcdef";
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                [SupervisorEndpointAuthority.ControlTokenConfigurationKey] = canonicalToken,
                [SupervisorEndpointAuthority.LegacySupervisorTokenConfigurationKey] = legacyToken
            })
            .Build();
        var context = new DefaultHttpContext();
        context.Request.Headers[SupervisorEndpointAuthority.HeaderName] = canonicalToken;

        Assert.True(SupervisorEndpointAuthority.HasAuthority(context, configuration));

        context.Request.Headers[SupervisorEndpointAuthority.HeaderName] = legacyToken;
        Assert.False(SupervisorEndpointAuthority.HasAuthority(context, configuration));
    }

    [Fact]
    public void SupervisorHealthAuthorityKeepsLegacyFallbackWhenControlTokenIsAbsent()
    {
        const string legacyToken = "legacy-supervisor-token-0123456789abcdef";
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                [SupervisorEndpointAuthority.LegacySupervisorTokenConfigurationKey] = legacyToken
            })
            .Build();
        var context = new DefaultHttpContext();
        context.Request.Headers[SupervisorEndpointAuthority.HeaderName] = legacyToken;

        Assert.True(SupervisorEndpointAuthority.HasAuthority(context, configuration));
    }

    [Fact]
    public void McpToolCatalogIsStrictlyReadOnly()
    {
        var expected = new[]
        {
            "get_system_health",
            "get_runtime_state",
            "get_strategy_scorecard",
            "get_trade_lifecycle",
            "get_journal_consistency",
            "get_recent_anomalies",
            "get_build_and_ci_state",
            "get_config_summary_non_secret",
            "get_evidence_by_id"
        };

        Assert.Equal(expected, SupervisorMcpToolCatalog.Names);
        Assert.All(
            SupervisorMcpToolCatalog.Names,
            name => Assert.StartsWith("get_", name, StringComparison.Ordinal));
        var combined = string.Join('|', SupervisorMcpToolCatalog.Names).ToLowerInvariant();
        foreach (var forbidden in new[]
                 {
                     "place_order",
                     "cancel",
                     "modify",
                     "leverage",
                     "stop_loss",
                     "take_profit",
                     "transfer",
                     "withdraw",
                     "risk_limit",
                     "start_trade"
                 })
        {
            Assert.DoesNotContain(forbidden, combined, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void McpRateLimiterIsBoundedPerSessionAndRecoversAfterWindow()
    {
        var time = new MutableTimeProvider(
            new DateTimeOffset(2026, 8, 14, 9, 30, 0, TimeSpan.Zero));
        var limiter = new SupervisorMcpRateLimiter(time);

        for (var request = 0; request < SupervisorMcpRateLimiter.MaximumRequestsPerWindow; request++)
        {
            Assert.True(limiter.TryAcquire("support-aabbccdd"));
        }

        Assert.False(limiter.TryAcquire("support-aabbccdd"));
        Assert.True(limiter.TryAcquire("support-other"));

        time.Advance(SupervisorMcpRateLimiter.Window);
        Assert.True(limiter.TryAcquire("support-aabbccdd"));
        Assert.False(limiter.TryAcquire(string.Empty));
    }

    [Fact]
    public void McpAuditLedgerNeverNeedsCredentialMaterial()
    {
        var ledger = new SupervisorMcpAuditLedger();
        ledger.Record(
            new SupervisorMcpAuditEvent(
                new DateTimeOffset(2026, 8, 14, 9, 30, 0, TimeSpan.Zero),
                "support-aabbccdd",
                "tools/call:get_runtime_state",
                true,
                "audit-1"));

        var auditEvent = Assert.Single(ledger.Snapshot());
        Assert.Equal("support-aabbccdd", auditEvent.SessionId);
        Assert.DoesNotContain("token", auditEvent.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("authorization", auditEvent.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    private static SupervisorSupportSessionRegistrationContract Registration(
        DateTimeOffset expiresAtUtc) =>
        new(
            Token,
            expiresAtUtc,
            SupervisorSupportSessionRegistry.RequiredScope,
            [Evidence()]);

    private static SupervisorEvidenceContract Evidence(
        string summary = "scanner completed cycle") =>
        new(
            "runtime.scan.42",
            "runtime",
            "scannerHeartbeat",
            new DateTimeOffset(2026, 8, 14, 9, 29, 0, TimeSpan.Zero),
            summary,
            "info",
            "local_live_trade_controller",
            "1.2.0-rc.3+126",
            "scan-42",
            new Dictionary<string, string>
            {
                ["state"] = "armed"
            });

    private sealed class MutableTimeProvider(DateTimeOffset now) : TimeProvider
    {
        private DateTimeOffset _now = now;

        public override DateTimeOffset GetUtcNow() => _now;

        public void Advance(TimeSpan amount) => _now += amount;
    }
}
