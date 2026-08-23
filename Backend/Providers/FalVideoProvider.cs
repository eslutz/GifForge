using GifForge.Backend.Models;
using Microsoft.Extensions.Logging;

namespace GifForge.Backend.Providers;

public sealed class FalVideoProvider : HttpVideoGenerationProvider
{
  public FalVideoProvider(HttpVideoGenerationProviderOptions options, HttpClient httpClient, ILogger? logger = null)
    : base(options, httpClient, logger)
  {
  }

  protected override VideoProviderSubmissionRequest BuildSubmissionRequest(
    VideoGenerationCapability capability,
    GenerationRequest request,
    VideoGenerationModel model
  ) =>
    new(
      model.ModelId,
      request.ExpandedPrompt ?? request.CleanedPrompt,
      request.NegativePrompt,
      InputTypeFor(capability),
      DurationSeconds(request),
      request.Options?.Width,
      request.Options?.Height,
      SourceMediaDataUrl(request)
    );

  private static string InputTypeFor(VideoGenerationCapability capability) =>
    capability switch
    {
      VideoGenerationCapability.TextToVideo => "text_to_video",
      VideoGenerationCapability.ImageToVideo => "image_to_video",
      VideoGenerationCapability.VideoToVideo => "video_to_video",
      _ => "text_to_video"
    };
}
