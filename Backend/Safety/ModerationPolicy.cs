using Gifster.Backend.Models;

namespace Gifster.Backend.Safety;

public static class ModerationPolicy
{
  private static readonly string[] BlockedTerms =
  [
    "child sexual",
    "minor sexual",
    "terrorist recruitment",
    "how to build a bomb"
  ];

  public static ValidationResult Validate(GenerationRequest? request)
  {
    if (request is null)
    {
      return ValidationResult.Invalid(StatusCodes.Status400BadRequest, "Request body must be a JSON object.");
    }

    if (request.Mode is not ("text_to_gif" or "image_to_gif"))
    {
      return ValidationResult.Invalid(StatusCodes.Status400BadRequest, "mode must be text_to_gif or image_to_gif.");
    }

    if (string.IsNullOrWhiteSpace(request.CleanedPrompt))
    {
      return ValidationResult.Invalid(StatusCodes.Status400BadRequest, "cleanedPrompt is required.");
    }

    if (request.CleanedPrompt.Length > 600 || (request.ExpandedPrompt ?? string.Empty).Length > 1600)
    {
      return ValidationResult.Invalid(StatusCodes.Status400BadRequest, "Prompt is too long.");
    }

    if (!string.IsNullOrEmpty(request.Caption?.Text) && request.Caption.Text.Length > 64)
    {
      return ValidationResult.Invalid(StatusCodes.Status400BadRequest, "Caption is too long.");
    }

    if (request.Mode == "image_to_gif")
    {
      if (request.SourceImage is null || string.IsNullOrWhiteSpace(request.SourceImage.DataBase64))
      {
        return ValidationResult.Invalid(StatusCodes.Status400BadRequest, "sourceImage is required for image_to_gif.");
      }

      if (request.SourceImage.DataBase64.Length > 8_000_000)
      {
        return ValidationResult.Invalid(StatusCodes.Status413PayloadTooLarge, "sourceImage exceeds the demo upload limit.");
      }
    }

    var searchable = string.Join(' ', request.CleanedPrompt, request.ExpandedPrompt, request.Caption?.Text).ToLowerInvariant();
    if (BlockedTerms.Any(searchable.Contains))
    {
      return ValidationResult.Invalid(StatusCodes.Status422UnprocessableEntity, "Request failed moderation checks.");
    }

    return ValidationResult.Valid;
  }
}

public readonly record struct ValidationResult(bool IsValid, int StatusCode, string Message)
{
  public static ValidationResult Valid { get; } = new(true, StatusCodes.Status200OK, string.Empty);
  public static ValidationResult Invalid(int statusCode, string message) => new(false, statusCode, message);
}
