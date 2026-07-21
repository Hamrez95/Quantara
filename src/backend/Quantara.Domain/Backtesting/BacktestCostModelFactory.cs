namespace Quantara.Domain.Backtesting;

public enum BacktestCostModelCode
{
    Created,
    InvalidVersion,
    InvalidSpread,
    InvalidSlippage,
    InvalidImpact,
    InvalidFee,
    InvalidParticipation,
    InvalidLatency
}

public sealed record BacktestCostModelResult(
    bool IsCreated,
    IReadOnlyList<BacktestCostModelCode> RejectionReasons,
    BacktestCostModel? Model);

public static class BacktestCostModelFactory
{
    public static BacktestCostModelResult Create(
        string version,
        decimal halfSpreadBps,
        decimal baseSlippageBps,
        decimal impactBpsAtMaximumParticipation,
        decimal takerFeeBps,
        decimal maximumVolumeParticipation,
        int latencyBars)
    {
        var rejections = new HashSet<BacktestCostModelCode>();
        if (string.IsNullOrWhiteSpace(version)
            || version.Length > 128
            || !string.Equals(version, version.Trim(), StringComparison.Ordinal))
        {
            rejections.Add(BacktestCostModelCode.InvalidVersion);
        }

        ValidateBps(
            halfSpreadBps,
            BacktestCostModelCode.InvalidSpread,
            rejections);
        ValidateBps(
            baseSlippageBps,
            BacktestCostModelCode.InvalidSlippage,
            rejections);
        ValidateBps(
            impactBpsAtMaximumParticipation,
            BacktestCostModelCode.InvalidImpact,
            rejections);
        ValidateBps(
            takerFeeBps,
            BacktestCostModelCode.InvalidFee,
            rejections);

        if (maximumVolumeParticipation <= 0m
            || maximumVolumeParticipation > 1m)
        {
            rejections.Add(BacktestCostModelCode.InvalidParticipation);
        }

        if (latencyBars < 1 || latencyBars > 10_000)
        {
            rejections.Add(BacktestCostModelCode.InvalidLatency);
        }

        if (rejections.Count > 0)
        {
            return new BacktestCostModelResult(
                false,
                Array.AsReadOnly(rejections.Order().ToArray()),
                null);
        }

        var fingerprintSha256 = CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-backtest-cost-model-v1");
            CanonicalResearchHash.Append(builder, version);
            CanonicalResearchHash.Append(builder, halfSpreadBps);
            CanonicalResearchHash.Append(builder, baseSlippageBps);
            CanonicalResearchHash.Append(
                builder,
                impactBpsAtMaximumParticipation);
            CanonicalResearchHash.Append(builder, takerFeeBps);
            CanonicalResearchHash.Append(builder, maximumVolumeParticipation);
            CanonicalResearchHash.Append(builder, latencyBars);
        });

        return new BacktestCostModelResult(
            true,
            Array.Empty<BacktestCostModelCode>(),
            new BacktestCostModel(
                version,
                halfSpreadBps,
                baseSlippageBps,
                impactBpsAtMaximumParticipation,
                takerFeeBps,
                maximumVolumeParticipation,
                latencyBars,
                fingerprintSha256));
    }

    private static void ValidateBps(
        decimal value,
        BacktestCostModelCode rejection,
        HashSet<BacktestCostModelCode> rejections)
    {
        if (value < 0m || value > 10_000m)
        {
            rejections.Add(rejection);
        }
    }
}

internal sealed class StableDeterministicRandom : IDeterministicRandom
{
    private ulong _state;

    public StableDeterministicRandom(int seed)
    {
        _state = unchecked((ulong)(uint)seed) + 0x9E3779B97F4A7C15UL;
        if (_state == 0UL)
        {
            _state = 0xD1B54A32D192ED03UL;
        }
    }

    public uint NextUInt32()
    {
        var value = NextUInt64();
        return (uint)(value >> 32);
    }

    public decimal NextUnitDecimal()
    {
        return NextUInt32() / ((decimal)uint.MaxValue + 1m);
    }

    private ulong NextUInt64()
    {
        var value = _state;
        value ^= value >> 12;
        value ^= value << 25;
        value ^= value >> 27;
        _state = value;
        return value * 2685821657736338717UL;
    }
}

