using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Quantara.Infrastructure.Persistence;

public sealed class QuantaraDbContextFactory
    : IDesignTimeDbContextFactory<QuantaraDbContext>
{
    public QuantaraDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable(
            "POSTGRES_CONNECTION")
            ?? "Host=localhost;Port=5432;Database=quantara;Username=quantara;Password=quantara_dev_only";
        var optionsBuilder = new DbContextOptionsBuilder<QuantaraDbContext>();
        optionsBuilder.UseNpgsql(
            connectionString,
            options => options.MigrationsAssembly(
                typeof(QuantaraDbContext).Assembly.FullName));
        return new QuantaraDbContext(optionsBuilder.Options);
    }
}

