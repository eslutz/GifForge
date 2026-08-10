using System.Globalization;
using GifForge.Backend.Configuration;
using Microsoft.Extensions.Configuration.AzureAppConfiguration;
using Microsoft.Extensions.Logging;

namespace GifForge.Backend.Costs;

public sealed class ModelCostRefreshCoordinator(
  ProviderPricingRegistry registry,
  AppConfigurationCostWriter writer,
  IAppConfigurationCostStore store,
  IRefreshLeaseFactory leaseFactory,
  ModelCostCacheOptions options,
  IConfiguration configuration,
  IConfigurationRefresherProvider refresherProvider,
  ILogger<ModelCostRefreshCoordinator> logger
)
{
  private const decimal DefaultMinimumDeltaUsd = 0.000001m;

  public async Task<ProviderRefreshResult> RefreshProviderAsync(string providerName, CancellationToken cancellationToken)
  {
    var provider = registry.Providers([providerName]).SingleOrDefault();
    if (provider.Source is null) throw new ArgumentException($"Unknown model cost provider '{providerName}'.", nameof(providerName));

    var result = await RefreshProviderUnderLeaseAsync(provider.Source, provider.Mappings, force: true, cancellationToken: cancellationToken);
    await RefreshConfigurationAsync(cancellationToken);
    return result;
  }

  public async Task<IReadOnlyList<ProviderRefreshResult>> RefreshAllAsync(CancellationToken cancellationToken)
  {
    var results = new List<ProviderRefreshResult>();
    foreach (var (source, mappings) in registry.Providers())
    {
      results.Add(await RefreshProviderAsync(source.ProviderName, cancellationToken));
    }
    return results;
  }

  public async Task EnsureFreshAsync(IEnumerable<string> providerNames, CancellationToken cancellationToken)
  {
    foreach (var providerName in providerNames.Distinct(StringComparer.OrdinalIgnoreCase))
    {
      var mappings = registry.MappingsFor(providerName);
      if (mappings.Count == 0) throw new InvalidOperationException($"No model cost mappings exist for provider '{providerName}'.");

      var timestamp = await ReadTimestampAsync(providerName, cancellationToken);
      var cache = await ReadCostsAsync(mappings, cancellationToken);
      if (timestamp is not null && DateTimeOffset.UtcNow - timestamp.Value < options.Ttl && cache.Values.All(value => value is not null)) continue;

      var provider = registry.Providers([providerName]).Single();
      var result = await RefreshProviderUnderLeaseAsync(provider.Source, mappings, force: false, cancellationToken: cancellationToken);
      await RefreshConfigurationAsync(cancellationToken);
      if (!result.Succeeded && cache.Values.Any(value => value is null))
      {
        throw new InvalidOperationException($"Model cost refresh failed for provider {providerName} and no complete cached cost is available.");
      }
    }
  }

  private async Task<ProviderRefreshResult> RefreshProviderUnderLeaseAsync(
    ProviderPricingSource source,
    IReadOnlyList<ProviderModelMapping> mappings,
    bool force,
    CancellationToken cancellationToken
  )
  {
    await using var lease = await leaseFactory.AcquireAsync(source.ProviderName, cancellationToken);
    using var renewal = new LeaseRenewalScope(lease, logger);
    var timestamp = await ReadTimestampAsync(source.ProviderName, cancellationToken);
    var cache = await ReadCostsAsync(mappings, cancellationToken);
    if (!force && timestamp is not null && DateTimeOffset.UtcNow - timestamp.Value < options.Ttl && cache.Values.All(value => value is not null))
    {
      return new ProviderRefreshResult(source.ProviderName, true, false, 0, timestamp, null);
    }

    try
    {
      var updates = await source.GetModelCostsUsdAsync(mappings, cancellationToken);
      var written = await writer.WriteChangedValuesAsync(updates, ParseMinimumDelta(), cancellationToken);
      var refreshedAt = DateTimeOffset.UtcNow;
      await store.SetValueAsync(TimestampKey(source.ProviderName), refreshedAt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture), cancellationToken);
      return new ProviderRefreshResult(source.ProviderName, true, false, written, refreshedAt, null);
    }
    catch (Exception error) when (error is not OperationCanceledException)
    {
      var failedTimestamp = await ReadTimestampAsync(source.ProviderName, cancellationToken);
      var age = failedTimestamp is null ? "unknown" : (DateTimeOffset.UtcNow - failedTimestamp.Value).ToString();
      logger.LogWarning("Model cost refresh failed for provider {ProviderName}; using cached values when available. Cached age: {CacheAge}.", source.ProviderName, age);
      return new ProviderRefreshResult(source.ProviderName, false, failedTimestamp is not null, 0, failedTimestamp, "Provider refresh failed.");
    }
  }

  private decimal ParseMinimumDelta() =>
    decimal.TryParse(configuration["GIFFORGE_COST_UPDATE_MIN_DELTA_USD"] ?? Environment.GetEnvironmentVariable("GIFFORGE_COST_UPDATE_MIN_DELTA_USD"), NumberStyles.Number, CultureInfo.InvariantCulture, out var value) && value >= 0
      ? value : DefaultMinimumDeltaUsd;

  private async Task<DateTimeOffset?> ReadTimestampAsync(string providerName, CancellationToken cancellationToken)
  {
    var raw = await store.GetValueAsync(TimestampKey(providerName), cancellationToken);
    return DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var value) ? value : null;
  }

  private async Task<Dictionary<string, decimal?>> ReadCostsAsync(IReadOnlyList<ProviderModelMapping> mappings, CancellationToken cancellationToken)
  {
    var result = new Dictionary<string, decimal?>(StringComparer.Ordinal);
    foreach (var mapping in mappings)
    {
      var raw = await store.GetValueAsync(mapping.AppConfigurationKey, cancellationToken);
      result[mapping.AppConfigurationKey] = decimal.TryParse(raw, NumberStyles.Number, CultureInfo.InvariantCulture, out var value) && value >= 0 ? value : null;
    }
    return result;
  }

  private async Task RefreshConfigurationAsync(CancellationToken cancellationToken)
  {
    if (refresherProvider is null) return;
    foreach (var refresher in refresherProvider.Refreshers)
    {
      await refresher.TryRefreshAsync(cancellationToken);
    }
  }

  public static string TimestampKey(string providerName) =>
    $"GIFFORGE_MODEL_COST_REFRESHED_AT_UTC_{new string(providerName.Where(char.IsLetterOrDigit).Select(char.ToUpperInvariant).ToArray())}";

  private sealed class LeaseRenewalScope : IDisposable
  {
    private readonly IRefreshLease lease;
    private readonly ILogger logger;
    private readonly CancellationTokenSource cancellation = new();
    private readonly Task renewal;

    public LeaseRenewalScope(IRefreshLease lease, ILogger logger)
    {
      this.lease = lease;
      this.logger = logger;
      renewal = RenewAsync();
    }

    private async Task RenewAsync()
    {
      try
      {
        while (true)
        {
          await Task.Delay(TimeSpan.FromSeconds(30), cancellation.Token);
          await lease.RenewAsync(cancellation.Token);
        }
      }
      catch (OperationCanceledException) { }
      catch (Exception) { logger.LogWarning("Model cost refresh lease renewal failed."); }
    }

    public void Dispose()
    {
      cancellation.Cancel();
      try { renewal.GetAwaiter().GetResult(); }
      catch (OperationCanceledException) { }
      cancellation.Dispose();
    }
  }
}
