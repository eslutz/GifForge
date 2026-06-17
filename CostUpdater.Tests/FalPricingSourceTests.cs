using Microsoft.Extensions.Configuration;

namespace GifForge.CostUpdater.Tests;

public sealed class FalPricingSourceTests
{
  [Fact]
  public async Task MapsFalPricingResponseToConfiguredCostKeys()
  {
    const string json = """
    {
      "models": [
        { "endpoint_id": "fal-ai/wan/v2.2-a14b/text-to-video", "price_usd": "0.031" },
        { "endpoint_id": "fal-ai/wan/v2.2-a14b/image-to-video", "price_usd": 0.041 }
      ]
    }
    """;

    var source = new FalPricingSource(
      new StaticHttpClientFactory(TestRegistry.JsonClient(json)),
      new ConfigurationBuilder().Build()
    );

    var updates = await source.GetModelCostsUsdAsync(
      [
        new(
          "fal.ai",
          "fal-ai/wan/v2.2-a14b/text-to-video",
          "GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO",
          "text"
        ),
        new(
          "fal.ai",
          "fal-ai/wan/v2.2-a14b/image-to-video",
          "GIFFORGE_MODEL_COST_USD_FAL_WAN22_IMAGE_TO_VIDEO",
          "image"
        )
      ],
      CancellationToken.None
    );

    Assert.Collection(
      updates,
      update =>
      {
        Assert.Equal("GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO", update.AppConfigurationKey);
        Assert.Equal(0.031m, update.CostUsd);
      },
      update =>
      {
        Assert.Equal("GIFFORGE_MODEL_COST_USD_FAL_WAN22_IMAGE_TO_VIDEO", update.AppConfigurationKey);
        Assert.Equal(0.041m, update.CostUsd);
      }
    );
  }

  [Fact]
  public async Task MalformedFalResponseProducesNoWrites()
  {
    var source = new FalPricingSource(
      new StaticHttpClientFactory(TestRegistry.JsonClient("""{ "models": [] }""")),
      new ConfigurationBuilder().Build()
    );

    await Assert.ThrowsAsync<InvalidOperationException>(() => source.GetModelCostsUsdAsync(
      [
        new("fal.ai", "missing", "GIFFORGE_MODEL_COST_USD_FAL_MISSING", "missing")
      ],
      CancellationToken.None
    ));
  }
}
