using System.Net;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;

namespace GifForge.CostUpdater.Tests;

internal sealed class StaticHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
  : HttpMessageHandler
{
  protected override Task<HttpResponseMessage> SendAsync(
    HttpRequestMessage request,
    CancellationToken cancellationToken
  ) => Task.FromResult(handler(request));
}

internal sealed class StaticHttpClientFactory(HttpClient client) : IHttpClientFactory
{
  public HttpClient CreateClient(string name) => client;
}

internal sealed class MemoryAppConfigurationStore(Dictionary<string, string?> values) : IAppConfigurationStore
{
  public Dictionary<string, string?> Values { get; } = values;
  public List<(string Key, string Value)> Writes { get; } = [];

  public Task<string?> GetValueAsync(string key, CancellationToken cancellationToken) =>
    Task.FromResult(Values.GetValueOrDefault(key));

  public Task SetValueAsync(string key, string value, CancellationToken cancellationToken)
  {
    Values[key] = value;
    Writes.Add((key, value));
    return Task.CompletedTask;
  }
}

internal sealed class StaticPricingSource(string providerName) : ProviderPricingSource
{
  public string ProviderName { get; } = providerName;

  public Task<IReadOnlyList<ModelCostUpdate>> GetModelCostsUsdAsync(
    IReadOnlyList<ProviderModelMapping> mappings,
    CancellationToken cancellationToken
  ) => Task.FromResult<IReadOnlyList<ModelCostUpdate>>([]);
}

internal static class TestRegistry
{
  public static ProviderPricingRegistry Create(
    IEnumerable<ProviderPricingSource> sources,
    IEnumerable<ProviderModelMapping> mappings
  ) => new(sources, mappings);

  public static AppConfigurationCostWriter Writer(
    MemoryAppConfigurationStore store,
    ProviderPricingRegistry registry
  ) => new(store, registry, NullLogger<AppConfigurationCostWriter>.Instance);

  public static HttpClient JsonClient(string json) =>
    new(
      new StaticHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
      {
        Content = new StringContent(json)
      })
    )
    {
      BaseAddress = new Uri("https://example.test/")
    };
}
