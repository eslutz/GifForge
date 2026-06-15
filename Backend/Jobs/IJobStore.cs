using GifForge.Backend.Models;
using GifForge.Backend.Providers;

namespace GifForge.Backend.Jobs;

public interface IJobStore
{
  Task<GenerationJob> CreateAsync(GenerationRequest request, ProviderJob providerJob, CancellationToken cancellationToken);
  Task<GenerationJob?> GetAsync(string id, CancellationToken cancellationToken);
  Task SaveAsync(GenerationJob job, CancellationToken cancellationToken);
  Task<int> DeleteExpiredAsync(DateTimeOffset expiresBefore, int maxCount, CancellationToken cancellationToken);
  GenerationJobStatus StatusFor(GenerationJob job);
}
