using Microsoft.Extensions.Configuration;
using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorStatusContractFactoryTests
{
    [Fact]
    public void ProductionNeverEnablesSmokeModeWithoutOpenAiCredential()
    {
        var configuration = Configuration(
            new Dictionary<string, string?>
            {
                ["QUANTARA_SUPERVISOR_SMOKE_MODE"] = "true"
            });

        var status = SupervisorStatusContractFactory.Create(
            configuration,
            "Production");

        Assert.False(status.Enabled);
        Assert.False(status.SmokeTest);
        Assert.False(status.AnalysisAvailable);
        Assert.True(status.ReadOnly);
        Assert.False(status.LiveTradingMutation);
        Assert.False(status.CredentialExposure);
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("Testing")]
    [InlineData("Staging")]
    public void ExplicitNonProductionSmokeModeProvesConnectivityOnly(
        string environmentName)
    {
        var configuration = Configuration(
            new Dictionary<string, string?>
            {
                ["QUANTARA_SUPERVISOR_SMOKE_MODE"] = "true"
            });

        var status = SupervisorStatusContractFactory.Create(
            configuration,
            environmentName);

        Assert.True(status.Enabled);
        Assert.Equal("mock-read-only", status.Model);
        Assert.True(status.SmokeTest);
        Assert.False(status.AnalysisAvailable);
        Assert.True(status.ReadOnly);
        Assert.False(status.LiveTradingMutation);
        Assert.False(status.CredentialExposure);
    }

    [Fact]
    public void OpenAiCredentialKeepsRealAnalysisStatusEvenWhenSmokeFlagExists()
    {
        var configuration = Configuration(
            new Dictionary<string, string?>
            {
                ["OPENAI_API_KEY"] = "sk-test-supervisor-0123456789abcdef",
                ["QUANTARA_SUPERVISOR_OPENAI_MODEL"] = "gpt-5.6",
                ["QUANTARA_SUPERVISOR_SMOKE_MODE"] = "true"
            });

        var status = SupervisorStatusContractFactory.Create(
            configuration,
            "Development");

        Assert.True(status.Enabled);
        Assert.Equal("gpt-5.6", status.Model);
        Assert.False(status.SmokeTest);
        Assert.True(status.AnalysisAvailable);
        Assert.True(status.ReadOnly);
        Assert.False(status.LiveTradingMutation);
        Assert.False(status.CredentialExposure);
    }

    [Fact]
    public void UnknownEnvironmentFailsClosedInsteadOfEnablingSmokeMode()
    {
        var configuration = Configuration(
            new Dictionary<string, string?>
            {
                ["QUANTARA_SUPERVISOR_SMOKE_MODE"] = "true"
            });

        var status = SupervisorStatusContractFactory.Create(
            configuration,
            "OwnerLaptop");

        Assert.False(status.Enabled);
        Assert.False(status.SmokeTest);
        Assert.False(status.AnalysisAvailable);
    }

    private static IConfiguration Configuration(
        IDictionary<string, string?> values) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(values)
            .Build();
}
