using GifForge.Backend.Models;
using GifForge.Backend.Providers;

namespace GifForge.Backend.Media;

public sealed class MediaNormalizationService
{
  public NormalizedGenerationInput Normalize(GenerationRequest request)
  {
    var capability = VideoGenerationInputClassifier.RequiredCapability(request);
    var durationSeconds = request.Options?.LoopSeconds is { } loopSeconds
      ? Math.Clamp((int)Math.Round(loopSeconds, MidpointRounding.AwayFromZero), 3, 5)
      : 4;

    return new NormalizedGenerationInput(
      capability,
      NormalizedMimeType(request),
      durationSeconds,
      capability == VideoGenerationCapability.VideoToVideo && IsLivePhotoMov(request.SourceMedia)
    );
  }

  private static string? NormalizedMimeType(GenerationRequest request)
  {
    if (request.SourceMedia is { } sourceMedia)
    {
      return sourceMedia.MimeType.Trim().ToLowerInvariant();
    }

    if (request.SourceImage is { } sourceImage)
    {
      return sourceImage.MimeType.Trim().ToLowerInvariant();
    }

    return null;
  }

  private static bool IsLivePhotoMov(SourceMediaRequest? sourceMedia) =>
    sourceMedia?.Role is "livePhotoPairedVideo" or "live-photo-paired-video";
}

public sealed record NormalizedGenerationInput(
  VideoGenerationCapability Capability,
  string? MimeType,
  int DurationSeconds,
  bool IsLivePhotoPairedVideo
);
