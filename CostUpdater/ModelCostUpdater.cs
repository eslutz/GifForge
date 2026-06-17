using Microsoft.Extensions.Logging;

namespace GifForge.CostUpdater;

public sealed class ModelCostUpdater(
  ProviderPricingRegistry registry,
  AppConfigurationCostWriter writer,
  ILogger<ModelCostUpdater> logger
)
{
  public async Task<CostUpdateSummary> UpdateAsync(
    decimal minimumDeltaUsd,
    bool dryRun,
    CancellationToken cancellationToken
  )
  {
    var providersChecked = 0;
    var providersSucceeded = 0;
    var providersFailed = 0;
    var valuesWritten = 0;

    foreach (var (source, mappings) in registry.Providers())
    {
      providersChecked++;
      try
      {
        var updates = await source.GetModelCostsUsdAsync(mappings, cancellationToken);
        valuesWritten += await writer.WriteChangedValuesAsync(updates, minimumDeltaUsd, dryRun, cancellationToken);
        providersSucceeded++;
      }
      catch (Exception ex)
      {
        providersFailed++;
        logger.LogError(ex, "Model cost update failed for provider {ProviderName}.", source.ProviderName);
      }
    }

    if (providersSucceeded == 0)
    {
      throw new InvalidOperationException("Model cost update failed for every registered provider.");
    }

    return new CostUpdateSummary(providersChecked, providersSucceeded, providersFailed, valuesWritten);
  }
}
