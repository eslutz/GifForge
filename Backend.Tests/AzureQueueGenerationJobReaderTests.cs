using GifForge.Backend.Queueing;

namespace GifForge.Backend.Tests;

public sealed class AzureQueueGenerationJobReaderTests
{
  [Fact]
  public void EmptyQueueMessageReturnsNoDequeuedJob()
  {
    Assert.Null(AzureQueueGenerationJobReader.ToDequeuedJob(null));
  }
}
