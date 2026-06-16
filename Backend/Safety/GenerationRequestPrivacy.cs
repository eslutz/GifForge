using GifForge.Backend.Models;

namespace GifForge.Backend.Safety;

public static class GenerationRequestPrivacy
{
  public static GenerationRequest SanitizeForJobState(GenerationRequest request) =>
    request with
    {
      OriginalPrompt = null,
      Caption = request.Caption is null
        ? null
        : request.Caption with
        {
          Text = null
        },
      SourceMedia = request.SourceMedia is null
        ? null
        : request.SourceMedia with
        {
          DataBase64 = string.Empty
        },
      SourceImage = request.SourceImage is null
        ? null
        : request.SourceImage with
        {
          DataBase64 = string.Empty
        }
    };
}
