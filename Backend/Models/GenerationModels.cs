namespace Gifster.Backend.Models;

public sealed record GenerationRequest(
  string? Id,
  string Mode,
  string? OriginalPrompt,
  string CleanedPrompt,
  string? ExpandedPrompt,
  string? NegativePrompt,
  CaptionRequest? Caption,
  SourceImageRequest? SourceImage,
  GenerationOptions? Options,
  string? ClientTraceId
);

public sealed record CaptionRequest(string Mode, string? Text);

public sealed record SourceImageRequest(
  string DataBase64,
  string MimeType,
  int Width,
  int Height
);

public sealed record GenerationOptions(
  int? Width,
  int? Height,
  double? LoopSeconds,
  string? StylePreset,
  string? MotionIntensity
);
