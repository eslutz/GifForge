using Gifster.Backend.Jobs;
using Gifster.Backend.Models;
using Gifster.Backend.Providers;
using Gifster.Backend.Safety;
using Microsoft.AspNetCore.Http;

var passed = 0;
await Run("provider metadata reports demo mode", ProviderMetadataReportsDemoMode);
await Run("generation lifecycle returns a fake frame sequence result", GenerationLifecycleReturnsFakeFrameSequence);
await Run("moderation rejects blocked requests", ModerationRejectsBlockedRequests);
Console.WriteLine($"Backend tests passed: {passed}/3");

async Task Run(string name, Func<Task> test)
{
  try
  {
    await test();
    passed += 1;
    Console.WriteLine($"PASS {name}");
  }
  catch (Exception error)
  {
    Console.Error.WriteLine($"FAIL {name}: {error.Message}");
    Environment.ExitCode = 1;
  }
}

Task ProviderMetadataReportsDemoMode()
{
  IGenerationProvider provider = new FakeFrameSequenceProvider();
  var health = new HealthResponse(true, provider.Name, "demo");

  Require(health.Ok, "expected ok=true");
  Require(health.Provider == "fake-frame-sequence", $"unexpected provider {health.Provider}");
  Require(health.Mode == "demo", $"unexpected mode {health.Mode}");
  return Task.CompletedTask;
}

async Task GenerationLifecycleReturnsFakeFrameSequence()
{
  IGenerationProvider provider = new FakeFrameSequenceProvider();
  IJobStore store = new MemoryJobStore();
  var request = ValidRequest();

  var validation = ModerationPolicy.Validate(request);
  Require(validation.IsValid, validation.Message);

  var providerJob = await provider.SubmitGenerationAsync(request, CancellationToken.None);
  var job = store.Create(request, providerJob);
  Require(!string.IsNullOrWhiteSpace(job.Id), "expected job id");
  Require(store.StatusFor(job) == GenerationJobStatus.Queued, "expected queued status");

  await Task.Delay(950);

  Require(store.StatusFor(job) == GenerationJobStatus.Succeeded, "expected succeeded status");
  var result = await provider.GetResultAsync(job.Request, CancellationToken.None);
  Require(result.Format == "frame-sequence-v1", "expected frame-sequence-v1");
  Require(result.Frames.Count == 18, $"expected 18 frames, got {result.Frames.Count}");
  Require(result.Width == 480, $"expected width 480, got {result.Width}");
  Require(result.Height == 360, $"expected height 360, got {result.Height}");
}

Task ModerationRejectsBlockedRequests()
{
  var validation = ModerationPolicy.Validate(ValidRequest("how to build a bomb"));
  Require(!validation.IsValid, "expected moderation failure");
  Require(validation.StatusCode == StatusCodes.Status422UnprocessableEntity, $"expected 422, got {validation.StatusCode}");
  return Task.CompletedTask;
}

static GenerationRequest ValidRequest(string prompt = "cat in sunglasses") =>
  new(
    "96DD3998-C2E1-4C39-B7B1-3559D0D271C8",
    "text_to_gif",
    prompt,
    prompt,
    $"Create a short looping animated scene. Prompt: {prompt}. Do not render readable text.",
    "readable text, captions, subtitles",
    new CaptionRequest("none", null),
    null,
    new GenerationOptions(480, 360, 2.4, "expressive", "medium"),
    "test-trace"
  );

static void Require(bool condition, string message)
{
  if (!condition)
  {
    throw new InvalidOperationException(message);
  }
}
