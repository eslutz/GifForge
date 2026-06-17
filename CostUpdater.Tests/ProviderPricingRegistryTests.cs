namespace GifForge.CostUpdater.Tests;

public sealed class ProviderPricingRegistryTests
{
  [Fact]
  public void RejectsDuplicateAppConfigurationKeys()
  {
    var mappings = new[]
    {
      Mapping("fal.ai", "fal-model-a", "GIFFORGE_MODEL_COST_USD_DUPLICATE"),
      Mapping("fal.ai", "fal-model-b", "GIFFORGE_MODEL_COST_USD_DUPLICATE")
    };

    var error = Assert.Throws<InvalidOperationException>(
      () => TestRegistry.Create([new StaticPricingSource("fal.ai")], mappings)
    );

    Assert.Contains("Duplicate App Configuration cost key", error.Message);
  }

  [Fact]
  public void RejectsMappingsWithoutPricingSource()
  {
    var mappings = new[]
    {
      Mapping("missing", "model", "GIFFORGE_MODEL_COST_USD_MISSING")
    };

    var error = Assert.Throws<InvalidOperationException>(
      () => TestRegistry.Create([new StaticPricingSource("fal.ai")], mappings)
    );

    Assert.Contains("No pricing source is registered", error.Message);
  }

  [Fact]
  public void AllowsProviderRemovalByRemovingMappings()
  {
    var registry = TestRegistry.Create(
      [new StaticPricingSource("fal.ai"), new StaticPricingSource("luma")],
      [Mapping("fal.ai", "fal-model", "GIFFORGE_MODEL_COST_USD_FAL_ONLY")]
    );

    Assert.Equal("GIFFORGE_MODEL_COST_USD_FAL_ONLY", Assert.Single(registry.KnownAppConfigurationKeys));
    Assert.Single(registry.Providers());
  }

  private static ProviderModelMapping Mapping(string provider, string sourceKey, string appConfigKey) =>
    new(provider, sourceKey, appConfigKey, sourceKey);
}
