using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchEvidenceEventTimeTests
{
    private static readonly Symbol BtcUsdt = new("BTCUSDT");
    private static readonly string RegistryHash = new('e', 64);
    private static readonly string RawHash = new('a', 64);
    private static readonly string NormalizedHash = new('b', 64);
    private static readonly DateTimeOffset RetrievedAt = new(
        2026,
        7,
        20,
        12,
        0,
        0,
        TimeSpan.Zero);

    [Fact]
    public void RejectsFutureEventTimeForObservedFact()
    {
        var result = Create(
            ResearchEvidenceKind.OfficialFact,
            RetrievedAt + TimeSpan.FromHours(1));

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidTimestamp,
            result.RejectionReasons);
    }

    [Fact]
    public void AcceptsFutureTimeForExplicitScheduledEvent()
    {
        var eventAt = RetrievedAt + TimeSpan.FromHours(1);
        var result = Create(
            ResearchEvidenceKind.ScheduledEvent,
            eventAt,
            eventAt + TimeSpan.FromMinutes(30));

        Assert.True(result.IsCreated);
        var envelope = Assert.IsType<ResearchEvidenceEnvelope>(result.Envelope);
        Assert.Equal(ResearchEvidenceKind.ScheduledEvent, envelope.Kind);
        Assert.Equal(eventAt, envelope.EventAt);
        Assert.Equal(eventAt + TimeSpan.FromMinutes(30), envelope.ExpiresAt);
    }

    [Fact]
    public void RejectsScheduledEventWithoutFutureEventTime()
    {
        var result = Create(
            ResearchEvidenceKind.ScheduledEvent,
            RetrievedAt,
            RetrievedAt + TimeSpan.FromHours(1));

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidTimestamp,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsScheduledEventWithoutExpiry()
    {
        var result = Create(
            ResearchEvidenceKind.ScheduledEvent,
            RetrievedAt + TimeSpan.FromHours(1));

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidTimestamp,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsScheduledEventThatExpiresBeforeEventTime()
    {
        var result = Create(
            ResearchEvidenceKind.ScheduledEvent,
            RetrievedAt + TimeSpan.FromHours(2),
            RetrievedAt + TimeSpan.FromHours(1));

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidTimestamp,
            result.RejectionReasons);
    }

    private static ResearchEvidenceBuildResult Create(
        ResearchEvidenceKind kind,
        DateTimeOffset? eventAt,
        DateTimeOffset? expiresAt = null)
    {
        var registryResult = ResearchSourceRegistrySnapshotFactory.Create(
            "1.0.0",
            RegistryHash,
            new DateTimeOffset(2026, 7, 20, 0, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 20, 0, 0, 0, TimeSpan.Zero),
            [
                new RegisteredResearchSource(
                    "fred-alfred-api",
                    new Uri("https://fred.stlouisfed.org/docs/api/fred/overview.html"),
                    ResearchDecisionRole.DirectFact,
                    ResearchCommercialUseStatus.ApprovedSubjectToTerms,
                    true)
            ]);
        if (!registryResult.IsCreated || registryResult.Snapshot is null)
        {
            throw new InvalidOperationException("Event-time registry fixture is invalid.");
        }

        return ResearchEvidenceEnvelopeFactory.Create(
            "evidence-event-1",
            registryResult.Snapshot,
            "fred-alfred-api",
            "provider-event-1",
            RetrievedAt,
            RetrievedAt - TimeSpan.FromMinutes(5),
            eventAt,
            RawHash,
            NormalizedHash,
            "event-v1",
            kind,
            [BtcUsdt],
            expiresAt);
    }
}
