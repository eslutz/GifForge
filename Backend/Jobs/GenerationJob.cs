using Gifster.Backend.Models;

namespace Gifster.Backend.Jobs;

public sealed record GenerationJob(
  string Id,
  GenerationRequest Request,
  string Provider,
  string ProviderJobId,
  DateTimeOffset CreatedAt,
  string? FailedMessage = null
);

public enum GenerationJobStatus
{
  Queued,
  Running,
  Succeeded,
  Failed
}

public static class GenerationJobStatusExtensions
{
  public static string JsonValue(this GenerationJobStatus status) =>
    status switch
    {
      GenerationJobStatus.Queued => "queued",
      GenerationJobStatus.Running => "running",
      GenerationJobStatus.Succeeded => "succeeded",
      GenerationJobStatus.Failed => "failed",
      _ => "failed"
    };
}
