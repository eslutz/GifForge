using GifForge.Backend.Configuration;
using GifForge.Backend.Costs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

namespace GifForge.Backend.Tests;

public sealed class ModelCostRefreshCoordinatorTests
{
  [Theory]
  [InlineData(null)]
  [InlineData("not-a-duration")]
  [InlineData("00:00:00")]
  [InlineData("-01:00:00")]
  public void InvalidTtlUsesOneDayDefault(string? raw)
  {
    var configuration = new ConfigurationBuilder()
      .AddInMemoryCollection(new Dictionary<string, string?> { ["GIFFORGE_MODEL_COST_CACHE_TTL"] = raw })
      .Build();

    Assert.Equal(TimeSpan.FromDays(1), ModelCostCacheOptions.FromConfiguration(configuration).Ttl);
  }

  [Fact]
  public async Task FreshProviderSkipsPricingRequest()
  {
    var source = new RecordingPricingSource("fal.ai", 0.09m);
    var store = CreateStore(DateTimeOffset.UtcNow.AddHours(-1), 0.03m);
    var coordinator = CreateCoordinator(store, source);

    await coordinator.EnsureFreshAsync(["fal.ai"], CancellationToken.None);

    Assert.Equal(0, source.RequestCount);
    Assert.Equal("0.03", store.Values["GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO"]);
  }

  [Fact]
  public async Task StaleProviderWritesCostsAndUtcTimestamp()
  {
    var source = new RecordingPricingSource("fal.ai", 0.09m);
    var store = CreateStore(DateTimeOffset.UtcNow.AddDays(-2), 0.03m);
    var coordinator = CreateCoordinator(store, source);

    await coordinator.EnsureFreshAsync(["fal.ai"], CancellationToken.None);

    Assert.Equal(1, source.RequestCount);
    Assert.Equal("0.09", store.Values["GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO"]);
    Assert.True(DateTimeOffset.TryParse(store.Values[ModelCostRefreshCoordinator.TimestampKey("fal.ai")], out var refreshedAt));
    Assert.Equal(TimeSpan.Zero, refreshedAt.Offset);
  }

  [Fact]
  public async Task FailedRefreshKeepsStaleCacheAndTimestamp()
  {
    var previous = DateTimeOffset.UtcNow.AddDays(-2);
    var source = new RecordingPricingSource("fal.ai", 0.09m, new HttpRequestException("pricing unavailable"));
    var store = CreateStore(previous, 0.03m);
    var coordinator = CreateCoordinator(store, source);

    await coordinator.EnsureFreshAsync(["fal.ai"], CancellationToken.None);

    Assert.Equal(1, source.RequestCount);
    Assert.Equal("0.03", store.Values["GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO"]);
    Assert.Equal(previous.ToString("O"), store.Values[ModelCostRefreshCoordinator.TimestampKey("fal.ai")]);
  }

  [Fact]
  public async Task ConcurrentStaleRequestsPerformOneRefresh()
  {
    var source = new RecordingPricingSource("fal.ai", 0.09m);
    var store = CreateStore(DateTimeOffset.UtcNow.AddDays(-2), 0.03m);
    var leases = new TestLeaseFactory();
    var first = CreateCoordinator(store, source, leases);
    var second = CreateCoordinator(store, source, leases);

    await Task.WhenAll(
      first.EnsureFreshAsync(["fal.ai"], CancellationToken.None),
      second.EnsureFreshAsync(["fal.ai"], CancellationToken.None)
    );

    Assert.Equal(1, source.RequestCount);
  }

  [Fact]
  public async Task MissingCacheAndFailedRefreshThrows()
  {
    var source = new RecordingPricingSource("fal.ai", 0.09m, new HttpRequestException("pricing unavailable"));
    var coordinator = CreateCoordinator(new MemoryCostStore([]), source);

    var error = await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.EnsureFreshAsync(["fal.ai"], CancellationToken.None));

    Assert.Contains("no complete cached cost", error.Message, StringComparison.OrdinalIgnoreCase);
  }

  [Fact]
  public async Task ManualRefreshForcesFreshProviderCall()
  {
    var source = new RecordingPricingSource("fal.ai", 0.09m);
    var store = CreateStore(DateTimeOffset.UtcNow, 0.03m);
    var coordinator = CreateCoordinator(store, source);

    await coordinator.RefreshProviderAsync("fal.ai", CancellationToken.None);

    Assert.Equal(1, source.RequestCount);
  }

  private static ModelCostRefreshCoordinator CreateCoordinator(
    MemoryCostStore store,
    RecordingPricingSource source,
    TestLeaseFactory? leases = null
  )
  {
    var registry = new ProviderPricingRegistry([source, new RecordingPricingSource("luma", 0.2m)]);
    return new(
      registry,
      new AppConfigurationCostWriter(store, registry, NullLogger<AppConfigurationCostWriter>.Instance),
      store,
      leases ?? new TestLeaseFactory(),
      new ModelCostCacheOptions(TimeSpan.FromDays(1)),
      new ConfigurationBuilder().Build(),
      new NoopConfigurationRefresherProvider(),
      NullLogger<ModelCostRefreshCoordinator>.Instance
    );
  }

  private static MemoryCostStore CreateStore(DateTimeOffset timestamp, decimal cost) => new(new Dictionary<string, string?>
  {
    [ModelCostRefreshCoordinator.TimestampKey("fal.ai")] = timestamp.ToString("O"),
    ["GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO"] = cost.ToString(System.Globalization.CultureInfo.InvariantCulture),
    ["GIFFORGE_MODEL_COST_USD_FAL_WAN22_IMAGE_TO_VIDEO"] = cost.ToString(System.Globalization.CultureInfo.InvariantCulture),
    ["GIFFORGE_MODEL_COST_USD_FAL_WAN22_VIDEO_TO_VIDEO"] = cost.ToString(System.Globalization.CultureInfo.InvariantCulture)
  });

  private sealed class RecordingPricingSource(string providerName, decimal cost, Exception? error = null) : ProviderPricingSource
  {
    public string ProviderName { get; } = providerName;
    public int RequestCount { get; private set; }

    public Task<IReadOnlyList<ModelCostUpdate>> GetModelCostsUsdAsync(IReadOnlyList<ProviderModelMapping> mappings, CancellationToken cancellationToken)
    {
      RequestCount++;
      if (error is not null) return Task.FromException<IReadOnlyList<ModelCostUpdate>>(error);
      return Task.FromResult<IReadOnlyList<ModelCostUpdate>>(mappings.Select(mapping => new ModelCostUpdate(mapping.AppConfigurationKey, cost)).ToArray());
    }
  }

  private sealed class MemoryCostStore(Dictionary<string, string?> values) : IAppConfigurationCostStore
  {
    public Dictionary<string, string?> Values { get; } = values;
    public Task<string?> GetValueAsync(string key, CancellationToken cancellationToken) => Task.FromResult(Values.GetValueOrDefault(key));
    public Task SetValueAsync(string key, string value, CancellationToken cancellationToken) { Values[key] = value; return Task.CompletedTask; }
  }

  private sealed class TestLeaseFactory : IRefreshLeaseFactory
  {
    private readonly SemaphoreSlim gate = new(1, 1);
    public async Task<IRefreshLease> AcquireAsync(string providerName, CancellationToken cancellationToken)
    {
      await gate.WaitAsync(cancellationToken);
      return new Lease(gate);
    }
    private sealed class Lease(SemaphoreSlim gate) : IRefreshLease
    {
      public Task RenewAsync(CancellationToken cancellationToken) => Task.CompletedTask;
      public ValueTask DisposeAsync() { gate.Release(); return ValueTask.CompletedTask; }
    }
  }
}
