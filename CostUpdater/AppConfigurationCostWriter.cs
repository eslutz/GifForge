using System.Globalization;
using Azure;
using Azure.Data.AppConfiguration;
using Azure.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace GifForge.CostUpdater;

public interface IAppConfigurationStore
{
  Task<string?> GetValueAsync(string key, CancellationToken cancellationToken);
  Task SetValueAsync(string key, string value, CancellationToken cancellationToken);
}

public sealed class AzureAppConfigurationStore : IAppConfigurationStore
{
  private readonly ConfigurationClient _client;

  public AzureAppConfigurationStore(IConfiguration configuration)
  {
    var endpoint = configuration["AZURE_APP_CONFIG_ENDPOINT"];
    if (string.IsNullOrWhiteSpace(endpoint))
    {
      throw new InvalidOperationException("AZURE_APP_CONFIG_ENDPOINT is required for model cost updates.");
    }

    var managedIdentityClientId = configuration["AZURE_CLIENT_ID"];
    var credential = string.IsNullOrWhiteSpace(managedIdentityClientId)
      ? new DefaultAzureCredential()
      : new DefaultAzureCredential(new DefaultAzureCredentialOptions
      {
        ManagedIdentityClientId = managedIdentityClientId
      });

    _client = new ConfigurationClient(new Uri(endpoint), credential);
  }

  public async Task<string?> GetValueAsync(string key, CancellationToken cancellationToken)
  {
    try
    {
      var response = await _client.GetConfigurationSettingAsync(key, label: null, cancellationToken);
      return response.Value.Value;
    }
    catch (RequestFailedException ex) when (ex.Status == 404)
    {
      return null;
    }
  }

  public async Task SetValueAsync(string key, string value, CancellationToken cancellationToken)
  {
    await _client.SetConfigurationSettingAsync(key, value, label: null, cancellationToken);
  }
}

public sealed class AppConfigurationCostWriter(
  IAppConfigurationStore store,
  ProviderPricingRegistry registry,
  ILogger<AppConfigurationCostWriter> logger
)
{
  public async Task<int> WriteChangedValuesAsync(
    IReadOnlyList<ModelCostUpdate> updates,
    decimal minimumDeltaUsd,
    bool dryRun,
    CancellationToken cancellationToken
  )
  {
    if (minimumDeltaUsd < 0)
    {
      throw new InvalidOperationException("Minimum model cost update delta cannot be negative.");
    }

    var seenKeys = new HashSet<string>(StringComparer.Ordinal);
    var written = 0;

    foreach (var update in updates)
    {
      ValidateUpdate(update, seenKeys);

      var currentValue = await store.GetValueAsync(update.AppConfigurationKey, cancellationToken);
      if (
        decimal.TryParse(currentValue, NumberStyles.Number, CultureInfo.InvariantCulture, out var currentCost)
        && Math.Abs(currentCost - update.CostUsd) < minimumDeltaUsd
      )
      {
        continue;
      }

      var nextValue = FormatCost(update.CostUsd);
      if (dryRun)
      {
        logger.LogInformation(
          "Dry run: would update App Configuration model cost {AppConfigurationKey} from {OldValue} to {NewValue}.",
          update.AppConfigurationKey,
          currentValue ?? "<unset>",
          nextValue
        );
        continue;
      }

      await store.SetValueAsync(update.AppConfigurationKey, nextValue, cancellationToken);
      written++;

      logger.LogInformation(
        "Updated App Configuration model cost {AppConfigurationKey} from {OldValue} to {NewValue}.",
        update.AppConfigurationKey,
        currentValue ?? "<unset>",
        nextValue
      );
    }

    return written;
  }

  private void ValidateUpdate(ModelCostUpdate update, HashSet<string> seenKeys)
  {
    if (!registry.KnownAppConfigurationKeys.Contains(update.AppConfigurationKey))
    {
      throw new InvalidOperationException($"Refusing to write unknown model cost key {update.AppConfigurationKey}.");
    }

    if (!update.AppConfigurationKey.StartsWith("GIFFORGE_MODEL_COST_USD_", StringComparison.Ordinal))
    {
      throw new InvalidOperationException($"Refusing to write non-cost key {update.AppConfigurationKey}.");
    }

    if (update.CostUsd < 0)
    {
      throw new InvalidOperationException($"Refusing to write negative model cost for {update.AppConfigurationKey}.");
    }

    if (!seenKeys.Add(update.AppConfigurationKey))
    {
      throw new InvalidOperationException($"Duplicate model cost update for {update.AppConfigurationKey}.");
    }
  }

  private static string FormatCost(decimal cost) =>
    cost.ToString("0.#############################", CultureInfo.InvariantCulture);
}
