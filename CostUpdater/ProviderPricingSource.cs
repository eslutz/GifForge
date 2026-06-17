namespace GifForge.CostUpdater;

public interface ProviderPricingSource
{
  string ProviderName { get; }

  Task<IReadOnlyList<ModelCostUpdate>> GetModelCostsUsdAsync(
    IReadOnlyList<ProviderModelMapping> mappings,
    CancellationToken cancellationToken
  );
}
