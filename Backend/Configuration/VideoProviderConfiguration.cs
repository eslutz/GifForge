using GifForge.Backend.Providers;
using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Configuration;

public static class VideoProviderConfiguration
{
  public static HttpVideoGenerationProviderOptions Fal(IConfiguration configuration) =>
    new(
      "fal.ai",
      configuration["GIFFORGE_FAL_SUBMIT_URL_TEMPLATE"] ?? "https://queue.fal.run/{modelId}",
      configuration["GIFFORGE_FAL_RESULT_URL_TEMPLATE"] ?? "https://queue.fal.run/{providerJobId}",
      AuthorizationHeader("Key", configuration["GIFFORGE_FAL_API_KEY"]),
      [
        Model(configuration, "GIFFORGE_FAL_TEXT_MODEL", "fal-ai/wan/v2.2-a14b/text-to-video", VideoGenerationCapability.TextToVideo, "GIFFORGE_FAL_TEXT_MODEL_COST_USD", 0.03m),
        Model(configuration, "GIFFORGE_FAL_IMAGE_MODEL", "fal-ai/wan/v2.2-a14b/image-to-video", VideoGenerationCapability.ImageToVideo, "GIFFORGE_FAL_IMAGE_MODEL_COST_USD", 0.04m),
        Model(configuration, "GIFFORGE_FAL_VIDEO_MODEL", "fal-ai/wan/v2.2-a14b/video-to-video", VideoGenerationCapability.VideoToVideo, "GIFFORGE_FAL_VIDEO_MODEL_COST_USD", 0.05m)
      ]
    );

  public static HttpVideoGenerationProviderOptions Luma(IConfiguration configuration) =>
    new(
      "luma",
      configuration["GIFFORGE_LUMA_SUBMIT_URL_TEMPLATE"] ?? "https://api.lumalabs.ai/dream-machine/v1/generations",
      configuration["GIFFORGE_LUMA_RESULT_URL_TEMPLATE"] ?? "https://api.lumalabs.ai/dream-machine/v1/generations/{providerJobId}",
      AuthorizationHeader("Bearer", configuration["GIFFORGE_LUMA_API_KEY"]),
      [
        Model(configuration, "GIFFORGE_LUMA_TEXT_MODEL", "ray-3.2", VideoGenerationCapability.TextToVideo, "GIFFORGE_LUMA_TEXT_MODEL_COST_USD", 0.16m),
        Model(configuration, "GIFFORGE_LUMA_IMAGE_MODEL", "ray-3.2", VideoGenerationCapability.ImageToVideo, "GIFFORGE_LUMA_IMAGE_MODEL_COST_USD", 0.18m),
        Model(configuration, "GIFFORGE_LUMA_VIDEO_MODEL", "ray-3.2", VideoGenerationCapability.VideoToVideo, "GIFFORGE_LUMA_VIDEO_MODEL_COST_USD", 0.22m)
      ]
    );

  public static bool IsEnabled(IConfiguration configuration, string providerName, bool fallback) =>
    configuration[$"GIFFORGE_{providerName}_ENABLED"] is { } value
      ? string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)
      : fallback;

  private static VideoGenerationModel Model(
    IConfiguration configuration,
    string modelKey,
    string defaultModel,
    VideoGenerationCapability capability,
    string costKey,
    decimal defaultCost
  ) =>
    new(
      configuration[modelKey] ?? defaultModel,
      capability,
      decimal.TryParse(configuration[costKey], out var cost) && cost >= 0 ? cost : defaultCost,
      !string.Equals(configuration[$"{modelKey}_ENABLED"], "false", StringComparison.OrdinalIgnoreCase)
    );

  private static string? AuthorizationHeader(string scheme, string? value) =>
    string.IsNullOrWhiteSpace(value) ? null : $"{scheme} {value}";
}
