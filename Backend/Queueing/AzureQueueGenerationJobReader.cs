using System.Text.Json;
using Azure.Storage.Queues;
using Azure.Storage.Queues.Models;

namespace GifForge.Backend.Queueing;

public sealed class AzureQueueGenerationJobReader : IGenerationJobQueueReader
{
  private readonly QueueClient queueClient;
  private readonly GenerationQueueOptions options;

  public AzureQueueGenerationJobReader(QueueClient queueClient, GenerationQueueOptions? options = null)
  {
    this.queueClient = queueClient;
    this.options = options ?? GenerationQueueOptions.Default;
  }

  public async Task<DequeuedGenerationJob?> DequeueAsync(CancellationToken cancellationToken)
  {
    // The default 30s visibility timeout is far shorter than a video generation,
    // so the message would reappear mid-processing and a second replica would
    // duplicate the provider work and the credit capture.
    var response = await queueClient
      .ReceiveMessageAsync(visibilityTimeout: options.VisibilityTimeout, cancellationToken: cancellationToken)
      .ConfigureAwait(false);
    if (!response.HasValue)
    {
      return null;
    }

    return ToDequeuedJob(response.Value);
  }

  internal static DequeuedGenerationJob? ToDequeuedJob(QueueMessage? message)
  {
    if (message is null)
    {
      return null;
    }

    var payload = JsonSerializer.Deserialize(
      message.MessageText,
      GifForgeJsonSerializerContext.Default.GenerationQueueMessage
    );

    return payload is null
      ? null
      : new DequeuedGenerationJob(payload.JobId, message.MessageId, message.PopReceipt, message.DequeueCount);
  }

  public async Task CompleteAsync(DequeuedGenerationJob job, CancellationToken cancellationToken)
  {
    await queueClient.DeleteMessageAsync(job.MessageId, job.PopReceipt, cancellationToken).ConfigureAwait(false);
  }
}
