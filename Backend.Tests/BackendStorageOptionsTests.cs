using GifForge.Backend.Configuration;
using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Tests;

public sealed class BackendStorageOptionsTests
{
  [Fact]
  public void FromConfigurationUsesAzureStorageResourceNames()
  {
    var configuration = new ConfigurationBuilder()
      .AddInMemoryCollection(new Dictionary<string, string?>
      {
        ["GIFFORGE_STORAGE_ACCOUNT_NAME"] = "gifforgenonprod",
        ["GIFFORGE_JOBS_TABLE_NAME"] = "GenerationJobs",
        ["GIFFORGE_APP_ATTEST_STATE_TABLE_NAME"] = "AppAttestState",
        ["GIFFORGE_GENERATION_QUEUE_NAME"] = "generation-jobs",
        ["GIFFORGE_RESULTS_CONTAINER_NAME"] = "provider-results",
        ["AZURE_CLIENT_ID"] = "11111111-1111-1111-1111-111111111111"
      })
      .Build();

    var options = BackendStorageOptions.FromConfiguration(configuration);

    Assert.True(options.IsConfigured);
    Assert.Equal("gifforgenonprod", options.StorageAccountName);
    Assert.Equal("GenerationJobs", options.JobsTableName);
    Assert.Equal("AppAttestState", options.AppAttestStateTableName);
    Assert.Equal("generation-jobs", options.GenerationQueueName);
    Assert.Equal("provider-results", options.ResultsContainerName);
    Assert.Equal("11111111-1111-1111-1111-111111111111", options.ManagedIdentityClientId);
  }

  [Fact]
  public void FromConfigurationKeepsLocalModeWhenStorageAccountIsMissing()
  {
    var options = BackendStorageOptions.FromConfiguration(new ConfigurationBuilder().Build());

    Assert.False(options.IsConfigured);
    Assert.Equal("GenerationJobs", options.JobsTableName);
    Assert.Equal("AppAttestState", options.AppAttestStateTableName);
  }
}
