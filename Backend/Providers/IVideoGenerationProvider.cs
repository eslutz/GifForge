using GifForge.Backend.Jobs;
using GifForge.Backend.Models;

namespace GifForge.Backend.Providers;

public interface IVideoGenerationProvider
{
  string Name { get; }
  IReadOnlyList<VideoGenerationModel> Models { get; }

  Task<ProviderJob> GenerateFromTextAsync(
    GenerationRequest request,
    VideoGenerationModel model,
    CancellationToken cancellationToken
  );

  Task<ProviderJob> GenerateFromImageAsync(
    GenerationRequest request,
    VideoGenerationModel model,
    CancellationToken cancellationToken
  );

  Task<ProviderJob> TransformVideoAsync(
    GenerationRequest request,
    VideoGenerationModel model,
    CancellationToken cancellationToken
  );

  Task<GeneratedMotionResult> GetResultAsync(GenerationJob job, CancellationToken cancellationToken);
}

public sealed record VideoGenerationModel(
  string ModelId,
  VideoGenerationCapability Capability,
  decimal EstimatedCostUsd,
  bool Enabled
);

public enum VideoGenerationCapability
{
  TextToVideo,
  ImageToVideo,
  VideoToVideo
}
