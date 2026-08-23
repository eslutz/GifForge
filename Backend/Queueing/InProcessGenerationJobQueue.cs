using System.Threading.Channels;
using GifForge.Backend.Jobs;

namespace GifForge.Backend.Queueing;

/// <summary>
/// Local-dev fallback used whenever Azure Storage isn't configured. Mirrors the
/// dispatch-then-process flow of the Azure Queue path entirely in-memory so a
/// generation submitted locally actually completes, instead of sitting "queued"
/// forever behind <see cref="NoopGenerationJobDispatcher"/> with nothing to read
/// the queue. Not meant to survive process restarts or run across replicas;
/// deployed environments always use the real Azure Queue Storage path.
/// </summary>
public sealed class InProcessGenerationJobQueue : IGenerationJobDispatcher, IGenerationJobQueueReader
{
  private readonly Channel<string> channel = Channel.CreateUnbounded<string>();

  public async Task DispatchAsync(GenerationJob job, CancellationToken cancellationToken)
  {
    await channel.Writer.WriteAsync(job.Id, cancellationToken).ConfigureAwait(false);
  }

  public async Task<DequeuedGenerationJob?> DequeueAsync(CancellationToken cancellationToken)
  {
    var jobId = await channel.Reader.ReadAsync(cancellationToken).ConfigureAwait(false);
    return new DequeuedGenerationJob(jobId, MessageId: jobId, PopReceipt: string.Empty);
  }

  // The channel read above already removes the item; there is no separate
  // acknowledgement step to perform in-memory.
  public Task CompleteAsync(DequeuedGenerationJob job, CancellationToken cancellationToken) =>
    Task.CompletedTask;
}
