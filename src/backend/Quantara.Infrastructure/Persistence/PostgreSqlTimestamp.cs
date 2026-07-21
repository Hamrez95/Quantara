namespace Quantara.Infrastructure.Persistence;

internal static class PostgreSqlTimestamp
{
    private const long TicksPerMicrosecond = 10;

    public static DateTimeOffset Normalize(DateTimeOffset value)
    {
        var utcValue = value.ToUniversalTime();
        var normalizedTicks = utcValue.Ticks
            - utcValue.Ticks % TicksPerMicrosecond;
        return new DateTimeOffset(normalizedTicks, TimeSpan.Zero);
    }
}

