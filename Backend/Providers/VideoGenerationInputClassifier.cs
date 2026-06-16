using GifForge.Backend.Models;

namespace GifForge.Backend.Providers;

public static class VideoGenerationInputClassifier
{
  public static VideoGenerationCapability RequiredCapability(GenerationRequest request)
  {
    if (request.SourceMedia is { } sourceMedia)
    {
      return CapabilityForSourceMedia(sourceMedia);
    }

    if (request.SourceImage is not null)
    {
      return VideoGenerationCapability.ImageToVideo;
    }

    return VideoGenerationCapability.TextToVideo;
  }

  private static VideoGenerationCapability CapabilityForSourceMedia(SourceMediaRequest sourceMedia)
  {
    var mimeType = sourceMedia.MimeType.Trim().ToLowerInvariant();
    var role = sourceMedia.Role?.Trim().ToLowerInvariant();
    var fileName = sourceMedia.FileName?.Trim().ToLowerInvariant() ?? string.Empty;

    if (mimeType is "image/gif" ||
        mimeType is "video/mp4" ||
        mimeType is "video/quicktime" ||
        fileName.EndsWith(".gif", StringComparison.Ordinal) ||
        fileName.EndsWith(".mp4", StringComparison.Ordinal) ||
        fileName.EndsWith(".mov", StringComparison.Ordinal) ||
        role is "video" or "livephotopairedvideo" or "live-photo-paired-video")
    {
      return VideoGenerationCapability.VideoToVideo;
    }

    if (mimeType is "image/jpeg" or "image/png" or "image/heic" or "image/heif")
    {
      return VideoGenerationCapability.ImageToVideo;
    }

    throw new GenerationPermanentFailureException(
      $"Unsupported source media content type '{sourceMedia.MimeType}'."
    );
  }
}
