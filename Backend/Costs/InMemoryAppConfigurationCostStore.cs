using System.Collections.Concurrent;

namespace GifForge.Backend.Costs;

/// <summary>
/// Local-dev fallback used when AZURE_APP_CONFIG_ENDPOINT isn't configured.
/// AzureAppConfigurationCostStore throws in its constructor without a real
/// endpoint, which otherwise makes every generation request fail on the model
/// cost refresh step before a provider is ever called. Values live only for
/// the process lifetime, matching the other in-memory local-dev stores
/// (MemoryJobStore, MemoryGenerationResultStore).
/// </summary>
public sealed class InMemoryAppConfigurationCostStore : IAppConfigurationCostStore
{
  private readonly ConcurrentDictionary<string, string> values = new(StringComparer.Ordinal);

  public Task<string?> GetValueAsync(string key, CancellationToken cancellationToken) =>
    Task.FromResult(values.TryGetValue(key, out var value) ? value : null);

  public Task SetValueAsync(string key, string value, CancellationToken cancellationToken)
  {
    values[key] = value;
    return Task.CompletedTask;
  }
}
