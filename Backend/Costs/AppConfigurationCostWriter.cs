using System.Globalization;
using Microsoft.Extensions.Logging;

namespace GifForge.Backend.Costs;

public sealed class AppConfigurationCostWriter(
  IAppConfigurationCostStore store,
  ProviderPricingRegistry registry,
  ILogger<AppConfigurationCostWriter> logger
)
{
  public async Task<int> WriteChangedValuesAsync(
    IReadOnlyList<ModelCostUpdate> updates,
    decimal minimumDeltaUsd,
    CancellationToken cancellationToken
  )
  {
    if (minimumDeltaUsd < 0) throw new InvalidOperationException("Minimum model cost update delta cannot be negative.");
    var seenKeys = new HashSet<string>(StringComparer.Ordinal);
    var written = 0;
    foreach (var update in updates)
    {
      ValidateUpdate(update, seenKeys);
      var currentValue = await store.GetValueAsync(update.AppConfigurationKey, cancellationToken);
      if (decimal.TryParse(currentValue, NumberStyles.Number, CultureInfo.InvariantCulture, out var currentCost) &&
          Math.Abs(currentCost - update.CostUsd) < minimumDeltaUsd) continue;

      var nextValue = update.CostUsd.ToString("0.#############################", CultureInfo.InvariantCulture);
      await store.SetValueAsync(update.AppConfigurationKey, nextValue, cancellationToken);
      written++;
      logger.LogInformation("Updated App Configuration model cost {AppConfigurationKey} from {OldValue} to {NewValue}.", update.AppConfigurationKey, currentValue ?? "<unset>", nextValue);
    }
    return written;
  }

  private void ValidateUpdate(ModelCostUpdate update, HashSet<string> seenKeys)
  {
    if (!registry.KnownAppConfigurationKeys.Contains(update.AppConfigurationKey)) throw new InvalidOperationException($"Refusing to write unknown model cost key {update.AppConfigurationKey}.");
    if (!update.AppConfigurationKey.StartsWith("GIFFORGE_MODEL_COST_USD_", StringComparison.Ordinal)) throw new InvalidOperationException($"Refusing to write non-cost key {update.AppConfigurationKey}.");
    if (update.CostUsd < 0) throw new InvalidOperationException($"Refusing to write negative model cost for {update.AppConfigurationKey}.");
    if (!seenKeys.Add(update.AppConfigurationKey)) throw new InvalidOperationException($"Duplicate model cost update for {update.AppConfigurationKey}.");
  }
}
