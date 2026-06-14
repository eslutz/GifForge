using System.Collections.Concurrent;
using Gifster.Backend.Models;
using Gifster.Backend.Providers;

namespace Gifster.Backend.Jobs;

public sealed class MemoryJobStore : IJobStore
{
  private readonly ConcurrentDictionary<string, GenerationJob> jobs = new();
  private readonly TimeSpan queuedDuration = TimeSpan.FromMilliseconds(250);
  private readonly TimeSpan completeDuration = TimeSpan.FromMilliseconds(800);

  public GenerationJob Create(GenerationRequest request, ProviderJob providerJob)
  {
    var job = new GenerationJob(
      Guid.NewGuid().ToString("D"),
      request,
      providerJob.Provider,
      providerJob.ProviderJobId,
      DateTimeOffset.UtcNow
    );

    jobs[job.Id] = job;
    return job;
  }

  public bool TryGet(string id, out GenerationJob job) =>
    jobs.TryGetValue(id, out job!);

  public GenerationJobStatus StatusFor(GenerationJob job)
  {
    if (!string.IsNullOrWhiteSpace(job.FailedMessage))
    {
      return GenerationJobStatus.Failed;
    }

    var age = DateTimeOffset.UtcNow - job.CreatedAt;
    if (age < queuedDuration)
    {
      return GenerationJobStatus.Queued;
    }

    return age < completeDuration
      ? GenerationJobStatus.Running
      : GenerationJobStatus.Succeeded;
  }
}
