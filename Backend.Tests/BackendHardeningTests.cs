using Azure.Storage.Queues.Models;
using GifForge.Backend.Jobs;
using GifForge.Backend.Providers;
using GifForge.Backend.Queueing;
using GifForge.Backend.Security;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Tests;

public sealed class QueuePoisonHandlingTests
{
  [Fact]
  public void DequeueCountIsMappedFromTheQueueMessage()
  {
    var message = QueuesModelFactory.QueueMessage(
      "message-1",
      "pop-receipt-1",
      """{"jobId":"job-123"}""",
      dequeueCount: 7
    );

    var dequeued = AzureQueueGenerationJobReader.ToDequeuedJob(message);

    Assert.NotNull(dequeued);
    Assert.Equal("job-123", dequeued.JobId);
    Assert.Equal(7, dequeued.DequeueCount);
  }

  [Fact]
  public void QueueOptionsDefaultsCoverLongGenerations()
  {
    var options = GenerationQueueOptions.FromConfiguration(new ConfigurationBuilder().Build());

    Assert.Equal(TimeSpan.FromMinutes(10), options.VisibilityTimeout);
    Assert.Equal(5, options.MaxDequeueCount);
  }

  [Fact]
  public async Task FailJobAsyncMarksQueuedJobFailed()
  {
    var store = new TableGenerationJobStore(new InMemoryGenerationJobTable());
    var provider = new FakeFrameSequenceProvider();
    var worker = new GenerationWorker(store, provider, new InMemoryGenerationResultStore());
    var providerJob = await provider.SubmitGenerationAsync(TestGenerationRequests.Valid(), CancellationToken.None);
    var job = await store.CreateAsync(TestGenerationRequests.Valid(), providerJob, CancellationToken.None);

    await worker.FailJobAsync(job.Id, "Poisoned.", "poison_message", CancellationToken.None);

    var failed = await store.GetAsync(job.Id, CancellationToken.None);
    Assert.NotNull(failed);
    Assert.Equal(GenerationJobStatus.Failed, failed.Status);
    Assert.Equal("Poisoned.", failed.FailedMessage);
  }

  [Fact]
  public async Task FailJobAsyncLeavesCompletedJobsUntouched()
  {
    var store = new TableGenerationJobStore(new InMemoryGenerationJobTable());
    var provider = new FakeFrameSequenceProvider();
    var worker = new GenerationWorker(store, provider, new InMemoryGenerationResultStore());
    var providerJob = await provider.SubmitGenerationAsync(TestGenerationRequests.Valid(), CancellationToken.None);
    var job = await store.CreateAsync(TestGenerationRequests.Valid(), providerJob, CancellationToken.None);
    await worker.ProcessJobAsync(job.Id, CancellationToken.None);

    await worker.FailJobAsync(job.Id, "Poisoned.", "poison_message", CancellationToken.None);

    var completed = await store.GetAsync(job.Id, CancellationToken.None);
    Assert.NotNull(completed);
    Assert.Equal(GenerationJobStatus.Succeeded, completed.Status);
  }
}

public sealed class CreditCaptureExpiryTests
{
  [Fact]
  public async Task CapturingAnExpiredReservationReleasesItInstead()
  {
    var store = new MemoryGifForgeAccountStore();
    var user = await store.CreateAnonymousUserAsync(CancellationToken.None);
    await store.GrantCreditsAsync(
      user.UserId,
      new VerifiedStoreKitTransaction(
        "txn-1",
        "txn-1",
        "dev.ericslutz.gifforge.credits.10",
        user.AppAccountToken,
        "Sandbox",
        "payload-hash"
      ),
      CancellationToken.None
    );
    var reservation = await store.TryReserveCreditsAsync(
      user.UserId,
      "job-expired",
      5,
      DateTimeOffset.UtcNow.AddMilliseconds(-1),
      CancellationToken.None
    );
    Assert.NotNull(reservation);

    await store.CaptureReservationAsync("job-expired", CancellationToken.None);

    var balance = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(10, balance.GrantedCredits);
    Assert.Equal(0, balance.CapturedDebits);
    Assert.Equal(0, balance.ReservedCredits);
    Assert.Equal(10, balance.AvailableCredits);
  }

  [Fact]
  public async Task CapturingALiveReservationStillDebits()
  {
    var store = new MemoryGifForgeAccountStore();
    var user = await store.CreateAnonymousUserAsync(CancellationToken.None);
    await store.GrantCreditsAsync(
      user.UserId,
      new VerifiedStoreKitTransaction(
        "txn-2",
        "txn-2",
        "dev.ericslutz.gifforge.credits.10",
        user.AppAccountToken,
        "Sandbox",
        "payload-hash"
      ),
      CancellationToken.None
    );
    _ = await store.TryReserveCreditsAsync(
      user.UserId,
      "job-live",
      5,
      DateTimeOffset.UtcNow.AddMinutes(60),
      CancellationToken.None
    );

    await store.CaptureReservationAsync("job-live", CancellationToken.None);

    var balance = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(5, balance.CapturedDebits);
    Assert.Equal(5, balance.AvailableCredits);
  }
}

public sealed class RateLimiterClientAddressTests
{
  private static GifForgeRateLimiter MakeLimiter(int generationMax) =>
    new(AccountSecurityOptions.FromConfiguration(new ConfigurationBuilder()
      .AddInMemoryCollection(new Dictionary<string, string?>
      {
        ["GIFFORGE_RATE_LIMIT_GENERATION_MAX"] = generationMax.ToString(),
        ["GIFFORGE_RATE_LIMIT_WINDOW_SECONDS"] = "60",
        ["GIFFORGE_AUTH_SIGNING_KEY"] = "test-signing-key"
      })
      .Build()));

  private static DefaultHttpContext ContextWithForwardedFor(string value)
  {
    var context = new DefaultHttpContext();
    context.Request.Headers["X-Forwarded-For"] = value;
    return context;
  }

  [Fact]
  public void ClientsAreKeyedByTheTrailingForwardedForEntry()
  {
    var limiter = MakeLimiter(generationMax: 1);

    // Same trailing (ingress-appended) address: second request is limited even if
    // the client varies its self-supplied leading entries.
    Assert.True(limiter.CheckGeneration(ContextWithForwardedFor("9.9.9.9, 1.2.3.4"), null).Allowed);
    Assert.False(limiter.CheckGeneration(ContextWithForwardedFor("8.8.8.8, 1.2.3.4"), null).Allowed);

    // A different real client address gets its own bucket.
    Assert.True(limiter.CheckGeneration(ContextWithForwardedFor("9.9.9.9, 5.6.7.8"), null).Allowed);
  }
}

public sealed class SigningKeyFailClosedTests
{
  private static IConfiguration Config(params (string Key, string Value)[] values) =>
    new ConfigurationBuilder()
      .AddInMemoryCollection(values.ToDictionary(pair => pair.Key, pair => (string?)pair.Value))
      .Build();

  [Fact]
  public void MissingSigningKeyThrows()
  {
    var error = Assert.Throws<InvalidOperationException>(() =>
      AccountSecurityOptions.FromConfiguration(Config(("GIFFORGE_AUTH_REQUIRED", "true"))));

    Assert.Contains("GIFFORGE_AUTH_SIGNING_KEY", error.Message);
  }

  // Closes the actual gap: previously, a missing signing key only threw when
  // GIFFORGE_AUTH_REQUIRED=true and demo bypass was off. Neither flag
  // exempts a deployment from needing a real key now — there is no
  // environment, including no-auth-required or demo-bypass local setups,
  // where a missing key silently falls back to a hardcoded default.
  [Fact]
  public void MissingSigningKeyThrowsEvenWithoutAuthRequired()
  {
    Assert.Throws<InvalidOperationException>(() => AccountSecurityOptions.FromConfiguration(Config()));
  }

  [Fact]
  public void DemoBypassStillRequiresASigningKey()
  {
    Assert.Throws<InvalidOperationException>(() => AccountSecurityOptions.FromConfiguration(Config(
      ("GIFFORGE_AUTH_REQUIRED", "true"),
      ("GIFFORGE_AUTH_DEMO_BYPASS", "true")
    )));
  }

  [Fact]
  public void AuthRequiredWithSigningKeySucceeds()
  {
    var options = AccountSecurityOptions.FromConfiguration(Config(
      ("GIFFORGE_AUTH_REQUIRED", "true"),
      ("GIFFORGE_AUTH_SIGNING_KEY", "a-real-signing-key")
    ));

    Assert.Equal("a-real-signing-key", options.SigningKey);
  }

  [Fact]
  public void DemoBypassKeepsLocalRunsWorking()
  {
    var options = AccountSecurityOptions.FromConfiguration(Config(
      ("GIFFORGE_AUTH_REQUIRED", "true"),
      ("GIFFORGE_AUTH_DEMO_BYPASS", "true"),
      ("GIFFORGE_AUTH_SIGNING_KEY", "a-real-signing-key")
    ));

    Assert.True(options.AuthRequired);
    Assert.True(options.AuthDemoBypassEnabled);
  }
}
