using Gifster.Backend.Models;
using Gifster.Backend.Providers;

namespace Gifster.Backend.Jobs;

public interface IJobStore
{
  GenerationJob Create(GenerationRequest request, ProviderJob providerJob);
  bool TryGet(string id, out GenerationJob job);
  GenerationJobStatus StatusFor(GenerationJob job);
}
