using Microsoft.Extensions.DependencyInjection;

namespace GifForge.CostUpdater;

public sealed class ProviderPricingRegistry
{
  private readonly IReadOnlyDictionary<string, ProviderPricingSource> _sourcesByProvider;

  public ProviderPricingRegistry(
    IEnumerable<ProviderPricingSource> sources,
    IEnumerable<ProviderModelMapping> mappings
  )
  {
    _sourcesByProvider = sources.ToDictionary(source => source.ProviderName, StringComparer.OrdinalIgnoreCase);
    Mappings = mappings.ToArray();
    Validate();
  }

  public IReadOnlyList<ProviderModelMapping> Mappings { get; }

  public IReadOnlySet<string> KnownAppConfigurationKeys =>
    Mappings.Select(mapping => mapping.AppConfigurationKey).ToHashSet(StringComparer.Ordinal);

  public IEnumerable<(ProviderPricingSource Source, IReadOnlyList<ProviderModelMapping> Mappings)> Providers()
  {
    foreach (var group in Mappings.GroupBy(mapping => mapping.ProviderName, StringComparer.OrdinalIgnoreCase))
    {
      yield return (_sourcesByProvider[group.Key], group.ToArray());
    }
  }

  public static ProviderPricingRegistry CreateDefault(IServiceProvider services) =>
    new(
      services.GetServices<ProviderPricingSource>(),
      [
        new(
          "fal.ai",
          "fal-ai/wan/v2.2-a14b/text-to-video",
          "GIFFORGE_MODEL_COST_USD_FAL_WAN22_TEXT_TO_VIDEO",
          "fal.ai Wan 2.2 text-to-video"
        ),
        new(
          "fal.ai",
          "fal-ai/wan/v2.2-a14b/image-to-video",
          "GIFFORGE_MODEL_COST_USD_FAL_WAN22_IMAGE_TO_VIDEO",
          "fal.ai Wan 2.2 image-to-video"
        ),
        new(
          "fal.ai",
          "fal-ai/wan/v2.2-a14b/video-to-video",
          "GIFFORGE_MODEL_COST_USD_FAL_WAN22_VIDEO_TO_VIDEO",
          "fal.ai Wan 2.2 video-to-video"
        ),
        new(
          "luma",
          "ray-3.2:text-to-video",
          "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_TEXT_TO_VIDEO",
          "Luma Ray 3.2 text-to-video"
        ),
        new(
          "luma",
          "ray-3.2:image-to-video",
          "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_IMAGE_TO_VIDEO",
          "Luma Ray 3.2 image-to-video"
        ),
        new(
          "luma",
          "ray-3.2:video-to-video",
          "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_VIDEO_TO_VIDEO",
          "Luma Ray 3.2 video-to-video"
        )
      ]
    );

  private void Validate()
  {
    var duplicateKey = Mappings
      .GroupBy(mapping => mapping.AppConfigurationKey, StringComparer.Ordinal)
      .FirstOrDefault(group => group.Count() > 1);

    if (duplicateKey is not null)
    {
      throw new InvalidOperationException($"Duplicate App Configuration cost key: {duplicateKey.Key}");
    }

    foreach (var mapping in Mappings)
    {
      if (!mapping.AppConfigurationKey.StartsWith("GIFFORGE_MODEL_COST_USD_", StringComparison.Ordinal))
      {
        throw new InvalidOperationException($"Cost updater mapping uses unsupported key: {mapping.AppConfigurationKey}");
      }

      if (!_sourcesByProvider.ContainsKey(mapping.ProviderName))
      {
        throw new InvalidOperationException($"No pricing source is registered for provider {mapping.ProviderName}.");
      }
    }
  }
}
