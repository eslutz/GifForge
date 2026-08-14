using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using GifForge.Backend.Jobs;
using GifForge.Backend.Models;
using GifForge.Backend.Providers;
using GifForge.Backend.Queueing;

namespace GifForge.Backend.Tests;

/// <summary>
/// Exercises the idempotent-submission fix under genuine concurrency (many
/// requests in flight at once via <c>Task.WhenAll</c>), not the sequential
/// "submit, await, submit again" shape every other idempotency-adjacent test
/// uses. Sequential awaits never actually overlap, so they can't catch a
/// check-then-act race between reading whether a job already exists and
/// creating it.
/// </summary>
public sealed class GenerationIdempotencyConcurrencyTests
{
  [Fact]
  public async Task ConcurrentSubmissionsWithTheSameClientRequestIdDispatchExactlyOnce()
  {
    var provider = new DelayedRecordingGenerationProvider(TimeSpan.FromMilliseconds(50));
    var dispatcher = new ThreadSafeRecordingGenerationJobDispatcher();
    await using var app = GifForgeBackendApp.Create(
      provider: provider,
      jobStore: new MemoryJobStore(),
      jobDispatcher: dispatcher
    );
    var baseAddress = await BackendRouteTestHost.StartAsync(app);
    using var client = new HttpClient { BaseAddress = baseAddress };

    var requestJson = JsonSerializer.Serialize(
      TestGenerationRequests.Valid(id: Guid.NewGuid().ToString("D")),
      JsonOptions()
    );

    const int concurrentRequests = 20;
    var responses = await Task.WhenAll(Enumerable.Range(0, concurrentRequests).Select(async _ =>
    {
      using var content = new StringContent(requestJson, Encoding.UTF8, "application/json");
      var response = await client.PostAsync("/v1/generations", content);
      var body = await response.Content.ReadFromJsonAsync<JobSubmissionResponse>();
      return (response.StatusCode, body);
    }));

    Assert.All(responses, result => Assert.Equal(System.Net.HttpStatusCode.Accepted, result.StatusCode));

    var distinctJobIds = responses.Select(result => result.body!.JobId).Distinct().ToArray();
    Assert.Single(distinctJobIds);

    // The real assertion: with 20 requests racing for the same idempotency
    // key, the provider — which stands in for a paid third-party API call —
    // must have been charged exactly once.
    Assert.Equal(1, provider.SubmissionCount);
    Assert.Single(dispatcher.JobIds.Distinct());
  }

  private static JsonSerializerOptions JsonOptions() =>
    new(JsonSerializerDefaults.Web);
}

/// <summary>Thread-safe counting provider with an artificial delay between
/// "start handling" and "finish handling" to widen the race window a
/// check-then-act idempotency bug would need to be caught by a test.</summary>
internal sealed class DelayedRecordingGenerationProvider : IGenerationProvider
{
  private readonly TimeSpan delay;
  private int submissionCount;

  public DelayedRecordingGenerationProvider(TimeSpan delay)
  {
    this.delay = delay;
  }

  public string Name => "delayed-recording-provider";

  public string Mode => "test";

  public int SubmissionCount => submissionCount;

  public async Task<ProviderJob> SubmitGenerationAsync(GenerationRequest request, CancellationToken cancellationToken)
  {
    var attempt = Interlocked.Increment(ref submissionCount);
    await Task.Delay(delay, cancellationToken);
    return new ProviderJob(Name, $"delayed-recording-provider-job-{attempt}");
  }

  public Task<GeneratedMotionResult> GetResultAsync(GenerationJob job, CancellationToken cancellationToken) =>
    throw new NotSupportedException();
}

internal sealed class ThreadSafeRecordingGenerationJobDispatcher : IGenerationJobDispatcher
{
  private readonly System.Collections.Concurrent.ConcurrentBag<string> jobIds = [];

  public IReadOnlyCollection<string> JobIds => jobIds;

  public Task DispatchAsync(GenerationJob job, CancellationToken cancellationToken)
  {
    jobIds.Add(job.Id);
    return Task.CompletedTask;
  }
}
