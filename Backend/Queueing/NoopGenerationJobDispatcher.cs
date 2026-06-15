using GifForge.Backend.Jobs;

namespace GifForge.Backend.Queueing;

public sealed class NoopGenerationJobDispatcher : IGenerationJobDispatcher
{
  public Task DispatchAsync(GenerationJob job, CancellationToken cancellationToken) =>
    Task.CompletedTask;
}
