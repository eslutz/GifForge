using System.Net;
using GifForge.Backend.Costs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

namespace GifForge.Backend.Tests;

public sealed class ModelCostPricingTests
{
  [Fact]
  public async Task FalPricingMapsConfiguredCostKeys()
  {
    var client = new HttpClient(new StaticHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
    {
      Content = new StringContent("""{"models":[{"endpoint_id":"fal-ai/wan/v2.2-a14b/text-to-video","price_usd":"0.031"}]}""")
    })) { BaseAddress = new Uri("https://example.test/") };
    var source = new FalPricingSource(new StaticHttpClientFactory(client), new ConfigurationBuilder().Build());
    var updates = await source.GetModelCostsUsdAsync(
      [new("fal.ai", "fal-ai/wan/v2.2-a14b/text-to-video", "GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO", "text")],
      CancellationToken.None);
    Assert.Equal(0.031m, Assert.Single(updates).CostUsd);
  }

  [Fact]
  public async Task FalPricingParsesRealApiResponseShape()
  {
    // Matches fal.ai's actual GET /v1/models/pricing response: {"prices":[{"endpoint_id":...,"unit_price":...}]},
    // and requires at least one endpoint_id query parameter or the real API returns HTTP 400.
    HttpRequestMessage? capturedRequest = null;
    var client = new HttpClient(new StaticHandler(request =>
    {
      capturedRequest = request;
      return new HttpResponseMessage(HttpStatusCode.OK)
      {
        Content = new StringContent(
          """{"prices":[{"endpoint_id":"fal-ai/wan/v2.2-a14b/text-to-video","unit_price":0.08,"unit":"seconds","currency":"USD"}],"next_cursor":null,"has_more":false}""")
      };
    })) { BaseAddress = new Uri("https://example.test/") };
    var source = new FalPricingSource(new StaticHttpClientFactory(client), new ConfigurationBuilder().Build());

    var updates = await source.GetModelCostsUsdAsync(
      [new("fal.ai", "fal-ai/wan/v2.2-a14b/text-to-video", "GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO", "text")],
      CancellationToken.None);

    Assert.Equal(0.08m, Assert.Single(updates).CostUsd);
    Assert.NotNull(capturedRequest);
    Assert.Contains("endpoint_id=fal-ai", capturedRequest.RequestUri!.Query);
  }

  [Fact]
  public void LumaPricingRejectsAmbiguousMissingFixture()
  {
    Assert.Throws<InvalidOperationException>(() => LumaPricingSource.ParseHtml(
      "<html>pricing changed</html>",
      [new("luma", "ray-3.2:text-to-video", "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_TEXT_TO_VIDEO", "text")]));
  }

  [Fact]
  public void RegistryRejectsDuplicateKnownKeys()
  {
    var error = Assert.Throws<InvalidOperationException>(() => new ProviderPricingRegistry(
      [new StaticPricingSource("fal.ai")],
      [new("fal.ai", "a", "GIFFORGE_MODEL_COST_USD_DUPLICATE", "a"), new("fal.ai", "b", "GIFFORGE_MODEL_COST_USD_DUPLICATE", "b")]));
    Assert.Contains("Duplicate App Configuration cost key", error.Message);
  }

  [Fact]
  public async Task WriterSkipsChangesBelowMinimumDelta()
  {
    var mapping = new ProviderModelMapping("fal.ai", "a", "GIFFORGE_MODEL_COST_USD_FAL_TEXT", "text");
    var registry = new ProviderPricingRegistry([new StaticPricingSource("fal.ai")], [mapping]);
    var store = new MemoryCostStore(new() { [mapping.AppConfigurationKey] = "0.03" });
    var written = await new AppConfigurationCostWriter(store, registry, NullLogger<AppConfigurationCostWriter>.Instance)
      .WriteChangedValuesAsync([new(mapping.AppConfigurationKey, 0.0300001m)], 0.000001m, CancellationToken.None);
    Assert.Equal(0, written);
    Assert.Empty(store.Writes);
  }

  private sealed class StaticPricingSource(string providerName) : ProviderPricingSource
  {
    public string ProviderName { get; } = providerName;
    public Task<IReadOnlyList<ModelCostUpdate>> GetModelCostsUsdAsync(IReadOnlyList<ProviderModelMapping> mappings, CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<ModelCostUpdate>>([]);
  }

  private sealed class StaticHttpClientFactory(HttpClient client) : IHttpClientFactory
  {
    public HttpClient CreateClient(string name) => client;
  }

  private sealed class StaticHandler(Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
  {
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(handler(request));
  }

  private sealed class MemoryCostStore(Dictionary<string, string?> values) : IAppConfigurationCostStore
  {
    public List<(string Key, string Value)> Writes { get; } = [];
    public Task<string?> GetValueAsync(string key, CancellationToken cancellationToken) => Task.FromResult(values.GetValueOrDefault(key));
    public Task SetValueAsync(string key, string value, CancellationToken cancellationToken) { values[key] = value; Writes.Add((key, value)); return Task.CompletedTask; }
  }
}
