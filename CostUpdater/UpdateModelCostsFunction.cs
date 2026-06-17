using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace GifForge.CostUpdater;

public sealed class UpdateModelCostsFunction(
  ModelCostUpdater updater,
  IConfiguration configuration,
  ILogger<UpdateModelCostsFunction> logger
)
{
  private const decimal DefaultMinimumDeltaUsd = 0.000001m;

  [Function("UpdateModelCosts")]
  public async Task RunAsync(
    [TimerTrigger("%GIFFORGE_COST_UPDATE_SCHEDULE%")] TimerInfo timerInfo,
    CancellationToken cancellationToken
  )
  {
    var minimumDeltaUsd = ParseMinimumDelta(configuration["GIFFORGE_COST_UPDATE_MIN_DELTA_USD"]);
    var dryRun = ParseBoolean(configuration["GIFFORGE_COST_UPDATE_DRY_RUN"], defaultValue: true);
    var summary = await updater.UpdateAsync(minimumDeltaUsd, dryRun, cancellationToken);

    logger.LogInformation(
      "Model cost update complete. Dry run: {DryRun}, providers checked: {ProvidersChecked}, succeeded: {ProvidersSucceeded}, failed: {ProvidersFailed}, values written: {ValuesWritten}.",
      dryRun,
      summary.ProvidersChecked,
      summary.ProvidersSucceeded,
      summary.ProvidersFailed,
      summary.ValuesWritten
    );
  }

  private static decimal ParseMinimumDelta(string? value) =>
    decimal.TryParse(
      value,
      System.Globalization.NumberStyles.Number,
      System.Globalization.CultureInfo.InvariantCulture,
      out var parsed
    ) && parsed >= 0
      ? parsed
      : DefaultMinimumDeltaUsd;

  private static bool ParseBoolean(string? value, bool defaultValue) =>
    string.IsNullOrWhiteSpace(value)
      ? defaultValue
      : bool.TryParse(value, out var parsed)
        ? parsed
        : defaultValue;
}
