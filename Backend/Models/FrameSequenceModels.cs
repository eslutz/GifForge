namespace Gifster.Backend.Models;

public sealed record FrameSequenceAsset(
  string Format,
  int Width,
  int Height,
  IReadOnlyList<FrameSpec> Frames,
  string PromptEcho
);

public sealed record FrameSpec(
  int Index,
  double Duration,
  string BackgroundHex,
  string AccentHex,
  double MotionOffset
);
