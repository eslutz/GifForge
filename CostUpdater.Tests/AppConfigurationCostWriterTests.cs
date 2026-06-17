namespace GifForge.CostUpdater.Tests;

public sealed class AppConfigurationCostWriterTests
{
  [Fact]
  public async Task WritesOnlyChangedKnownCostKeys()
  {
    var registry = RegistryWithKeys(
      "GIFFORGE_MODEL_COST_USD_FAL_TEXT",
      "GIFFORGE_MODEL_COST_USD_FAL_IMAGE"
    );
    var store = new MemoryAppConfigurationStore(new Dictionary<string, string?>
    {
      ["GIFFORGE_MODEL_COST_USD_FAL_TEXT"] = "0.03",
      ["GIFFORGE_MODEL_COST_USD_FAL_IMAGE"] = "0.04"
    });

    var written = await TestRegistry.Writer(store, registry).WriteChangedValuesAsync(
      [
        new("GIFFORGE_MODEL_COST_USD_FAL_TEXT", 0.03m),
        new("GIFFORGE_MODEL_COST_USD_FAL_IMAGE", 0.05m)
      ],
      0.000001m,
      dryRun: false,
      CancellationToken.None
    );

    Assert.Equal(1, written);
    Assert.Equal(("GIFFORGE_MODEL_COST_USD_FAL_IMAGE", "0.05"), Assert.Single(store.Writes));
  }

  [Fact]
  public async Task DryRunDoesNotWriteChangedKnownCostKeys()
  {
    var registry = RegistryWithKeys("GIFFORGE_MODEL_COST_USD_FAL_TEXT");
    var store = new MemoryAppConfigurationStore(new Dictionary<string, string?>
    {
      ["GIFFORGE_MODEL_COST_USD_FAL_TEXT"] = "0.03"
    });

    var written = await TestRegistry.Writer(store, registry).WriteChangedValuesAsync(
      [new("GIFFORGE_MODEL_COST_USD_FAL_TEXT", 0.05m)],
      0.000001m,
      dryRun: true,
      CancellationToken.None
    );

    Assert.Equal(0, written);
    Assert.Empty(store.Writes);
    Assert.Equal("0.03", store.Values["GIFFORGE_MODEL_COST_USD_FAL_TEXT"]);
  }

  [Fact]
  public async Task RejectsNegativeValues()
  {
    var registry = RegistryWithKeys("GIFFORGE_MODEL_COST_USD_FAL_TEXT");
    var store = new MemoryAppConfigurationStore([]);

    await Assert.ThrowsAsync<InvalidOperationException>(() => TestRegistry.Writer(store, registry)
      .WriteChangedValuesAsync(
        [new("GIFFORGE_MODEL_COST_USD_FAL_TEXT", -0.01m)],
        0.000001m,
        dryRun: false,
        CancellationToken.None
      ));

    Assert.Empty(store.Writes);
  }

  [Fact]
  public async Task NeverWritesProviderOrModelIdentityKeys()
  {
    var registry = RegistryWithKeys("GIFFORGE_MODEL_COST_USD_FAL_TEXT");
    var store = new MemoryAppConfigurationStore([]);

    await Assert.ThrowsAsync<InvalidOperationException>(() => TestRegistry.Writer(store, registry)
      .WriteChangedValuesAsync(
        [new("GIFFORGE_FAL_TEXT_MODEL", 0.01m)],
        0.000001m,
        dryRun: false,
        CancellationToken.None
      ));

    Assert.Empty(store.Writes);
  }

  private static ProviderPricingRegistry RegistryWithKeys(params string[] keys) =>
    TestRegistry.Create(
      [new StaticPricingSource("fal.ai")],
      keys.Select(key => new ProviderModelMapping("fal.ai", key, key, key))
    );
}
