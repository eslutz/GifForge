using Azure;
using Azure.Data.AppConfiguration;
using Azure.Identity;
using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Costs;

public interface IAppConfigurationCostStore
{
  Task<string?> GetValueAsync(string key, CancellationToken cancellationToken);
  Task SetValueAsync(string key, string value, CancellationToken cancellationToken);
}

public sealed class AzureAppConfigurationCostStore : IAppConfigurationCostStore
{
  private readonly ConfigurationClient client;

  public AzureAppConfigurationCostStore(IConfiguration configuration)
  {
    var endpoint = configuration["AZURE_APP_CONFIG_ENDPOINT"];
    if (string.IsNullOrWhiteSpace(endpoint)) throw new InvalidOperationException("AZURE_APP_CONFIG_ENDPOINT is required for model cost refresh.");
    var managedIdentityClientId = configuration["AZURE_CLIENT_ID"];
    var credential = string.IsNullOrWhiteSpace(managedIdentityClientId)
      ? new DefaultAzureCredential()
      : new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = managedIdentityClientId });
    client = new ConfigurationClient(new Uri(endpoint), credential);
  }

  public async Task<string?> GetValueAsync(string key, CancellationToken cancellationToken)
  {
    try
    {
      var response = await client.GetConfigurationSettingAsync(key, label: null, cancellationToken);
      return response.Value.Value;
    }
    catch (RequestFailedException error) when (error.Status == 404)
    {
      return null;
    }
  }

  public Task SetValueAsync(string key, string value, CancellationToken cancellationToken) =>
    client.SetConfigurationSettingAsync(key, value, label: null, cancellationToken);
}
