using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Configuration;

public sealed record BackendStorageOptions(
  string? StorageAccountName,
  string JobsTableName,
  string AppAttestStateTableName,
  string GenerationQueueName,
  string ResultsContainerName,
  string? ManagedIdentityClientId
)
{
  public bool IsConfigured => !string.IsNullOrWhiteSpace(StorageAccountName);

  public static BackendStorageOptions FromConfiguration(IConfiguration configuration) =>
    new(
      EmptyAsNull(configuration["GIFFORGE_STORAGE_ACCOUNT_NAME"]),
      configuration["GIFFORGE_JOBS_TABLE_NAME"] ?? "GenerationJobs",
      configuration["GIFFORGE_APP_ATTEST_STATE_TABLE_NAME"] ?? "AppAttestState",
      configuration["GIFFORGE_GENERATION_QUEUE_NAME"] ?? "generation-jobs",
      configuration["GIFFORGE_RESULTS_CONTAINER_NAME"] ?? "provider-results",
      EmptyAsNull(configuration["AZURE_CLIENT_ID"])
    );

  private static string? EmptyAsNull(string? value) =>
    string.IsNullOrWhiteSpace(value) ? null : value;
}
