using GifForge.Backend.Jobs;

namespace GifForge.Backend.Queueing;

public interface IGenerationJobDispatcher
{
  Task DispatchAsync(GenerationJob job, CancellationToken cancellationToken);
}
