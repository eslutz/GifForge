using GifForge.Backend.Jobs;
using GifForge.Backend.Models;

namespace GifForge.Backend.Providers;

public interface IGenerationProvider
{
  string Name { get; }
  string Mode { get; }
  Task<ProviderJob> SubmitGenerationAsync(GenerationRequest request, CancellationToken cancellationToken);
  Task<GeneratedMotionResult> GetResultAsync(GenerationJob job, CancellationToken cancellationToken);
}

public sealed record ProviderJob(string Provider, string ProviderJobId);
