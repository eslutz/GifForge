using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Queueing;

/// <summary>
/// Queue consumption settings. The visibility timeout must exceed the worst-case
/// provider generation time so a second worker replica never processes the same
/// message concurrently, and the dequeue-count ceiling turns repeatedly failing
/// messages into failed jobs instead of retrying them until job expiry.
/// </summary>
public sealed record GenerationQueueOptions(TimeSpan VisibilityTimeout, long MaxDequeueCount)
{
  public static GenerationQueueOptions Default { get; } = new(TimeSpan.FromMinutes(10), 5);

  public static GenerationQueueOptions FromConfiguration(IConfiguration configuration)
  {
    var visibilitySeconds = int.TryParse(configuration["GIFFORGE_QUEUE_VISIBILITY_SECONDS"], out var seconds) && seconds > 0
      ? seconds
      : (int)Default.VisibilityTimeout.TotalSeconds;
    var maxDequeueCount = long.TryParse(configuration["GIFFORGE_QUEUE_MAX_DEQUEUE_COUNT"], out var count) && count > 0
      ? count
      : Default.MaxDequeueCount;

    return new GenerationQueueOptions(TimeSpan.FromSeconds(visibilitySeconds), maxDequeueCount);
  }
}
