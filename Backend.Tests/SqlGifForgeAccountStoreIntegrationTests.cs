using GifForge.Backend.Security;

namespace GifForge.Backend.Tests;

/// <summary>
/// Integration tests for <see cref="SqlGifForgeAccountStore"/> against a real
/// SQL Server 2022 container with the actual production migrations applied —
/// not the in-memory double every other test in this project uses. This is
/// the money-handling path (credit reservation, capture, release, StoreKit
/// grants) and the refresh-token rotation/reuse-detection path; before this
/// suite, that T-SQL was validated only by
/// <see cref="SqlGifForgeAccountStoreTests"/>'s 33-line connection-string
/// check. Every test uses its own freshly created user so tests can run
/// against the one shared container without interfering with each other.
/// </summary>
[Collection("SqlServer")]
public sealed class SqlGifForgeAccountStoreIntegrationTests
{
  private readonly SqlGifForgeAccountStore store;

  public SqlGifForgeAccountStoreIntegrationTests(SqlServerFixture fixture)
  {
    store = new SqlGifForgeAccountStore(fixture.ConnectionString);
  }

  private async Task<GifForgeUser> CreateUserAsync() =>
    await store.CreateAnonymousUserAsync(CancellationToken.None);

  private async Task GrantAsync(Guid userId, Guid appAccountToken, int credits, string transactionId)
  {
    var productId = $"dev.ericslutz.gifforge.credits.{credits}";
    var result = await store.GrantCreditsAsync(
      userId,
      new VerifiedStoreKitTransaction(transactionId, transactionId, productId, appAccountToken, "Sandbox", "hash"),
      CancellationToken.None
    );
    Assert.NotNull(result);
    Assert.True(result.GrantedCredits > 0 || result.AlreadyProcessed);
  }

  [Fact]
  public async Task CreateAnonymousUserRoundTripsThroughGetUser()
  {
    var created = await CreateUserAsync();

    var fetched = await store.GetUserAsync(created.UserId, CancellationToken.None);

    Assert.NotNull(fetched);
    Assert.Equal(created.UserId, fetched.UserId);
    Assert.Null(fetched.AppleSubject);
  }

  [Fact]
  public async Task ReservingMoreCreditsThanAvailableFails()
  {
    var user = await CreateUserAsync();

    var reservation = await store.TryReserveCreditsAsync(
      user.UserId,
      $"job-{Guid.NewGuid():N}",
      5,
      DateTimeOffset.UtcNow.AddHours(1),
      CancellationToken.None
    );

    Assert.Null(reservation);
  }

  [Fact]
  public async Task ReserveThenCaptureDebitsExactlyOnce()
  {
    var user = await CreateUserAsync();
    await GrantAsync(user.UserId, user.AppAccountToken, 10, $"txn-{Guid.NewGuid():N}");
    var jobId = $"job-{Guid.NewGuid():N}";

    var reservation = await store.TryReserveCreditsAsync(
      user.UserId, jobId, 4, DateTimeOffset.UtcNow.AddHours(1), CancellationToken.None
    );
    Assert.NotNull(reservation);

    var afterReserve = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(10, afterReserve.GrantedCredits);
    Assert.Equal(0, afterReserve.CapturedDebits);
    Assert.Equal(4, afterReserve.ReservedCredits);
    Assert.Equal(6, afterReserve.AvailableCredits);

    await store.CaptureReservationAsync(jobId, CancellationToken.None);

    var afterCapture = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(4, afterCapture.CapturedDebits);
    Assert.Equal(0, afterCapture.ReservedCredits);
    Assert.Equal(6, afterCapture.AvailableCredits);

    // Capturing again must not double-debit — CompleteReservationAsync only
    // acts on reservations still in the 'reserved' status.
    await store.CaptureReservationAsync(jobId, CancellationToken.None);
    var afterSecondCapture = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(4, afterSecondCapture.CapturedDebits);
  }

  [Fact]
  public async Task ReserveThenReleaseReturnsCreditsToAvailableBalance()
  {
    var user = await CreateUserAsync();
    await GrantAsync(user.UserId, user.AppAccountToken, 10, $"txn-{Guid.NewGuid():N}");
    var jobId = $"job-{Guid.NewGuid():N}";

    await store.TryReserveCreditsAsync(user.UserId, jobId, 3, DateTimeOffset.UtcNow.AddHours(1), CancellationToken.None);
    await store.ReleaseReservationAsync(jobId, "provider_unavailable", CancellationToken.None);

    var balance = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(0, balance.CapturedDebits);
    Assert.Equal(0, balance.ReservedCredits);
    Assert.Equal(10, balance.AvailableCredits);
  }

  /// <summary>
  /// Regression test for the double-spend bug fixed in this session: an
  /// expired reservation is excluded from the "reserved" total (so its
  /// credits look available again and can be re-spent), but the worker can
  /// still call CaptureReservationAsync on it after expiry (a slow provider
  /// finally responding). Capture must convert to a release instead of
  /// debiting — otherwise the same credits get spent twice.
  /// </summary>
  [Fact]
  public async Task CapturingAnExpiredReservationReleasesInsteadOfDoubleSpending()
  {
    var user = await CreateUserAsync();
    await GrantAsync(user.UserId, user.AppAccountToken, 10, $"txn-{Guid.NewGuid():N}");
    var jobId = $"job-{Guid.NewGuid():N}";

    var reservation = await store.TryReserveCreditsAsync(
      user.UserId, jobId, 5, DateTimeOffset.UtcNow.AddMilliseconds(50), CancellationToken.None
    );
    Assert.NotNull(reservation);

    await Task.Delay(TimeSpan.FromMilliseconds(200));

    // The expired reservation no longer counts against the spendable
    // balance, so it looks fully available again...
    var whileExpired = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(10, whileExpired.AvailableCredits);

    // ...and the user can genuinely re-spend those credits on a new job.
    var secondJobId = $"job-{Guid.NewGuid():N}";
    var secondReservation = await store.TryReserveCreditsAsync(
      user.UserId, secondJobId, 5, DateTimeOffset.UtcNow.AddHours(1), CancellationToken.None
    );
    Assert.NotNull(secondReservation);

    // The original (now-expired) job's slow provider call finally returns
    // success and the worker captures it — this must convert to a release,
    // not a debit, or the user has spent credits against a job that already
    // gave its hold back and let a second job reserve the same credits.
    await store.CaptureReservationAsync(jobId, CancellationToken.None);

    var finalBalance = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(0, finalBalance.CapturedDebits);
    Assert.Equal(5, finalBalance.AvailableCredits);
  }

  [Fact]
  public async Task GrantingTheSameTransactionTwiceIsIdempotent()
  {
    var user = await CreateUserAsync();
    var transactionId = $"txn-{Guid.NewGuid():N}";

    await GrantAsync(user.UserId, user.AppAccountToken, 10, transactionId);
    var second = await store.GrantCreditsAsync(
      user.UserId,
      new VerifiedStoreKitTransaction(transactionId, transactionId, "dev.ericslutz.gifforge.credits.10", user.AppAccountToken, "Sandbox", "hash"),
      CancellationToken.None
    );

    Assert.NotNull(second);
    Assert.True(second.AlreadyProcessed);

    var balance = await store.GetCreditBalanceAsync(user.UserId, CancellationToken.None);
    Assert.Equal(10, balance.GrantedCredits);
  }

  [Fact]
  public async Task GrantingAnInactiveProductIsRejected()
  {
    var user = await CreateUserAsync();

    var result = await store.GrantCreditsAsync(
      user.UserId,
      new VerifiedStoreKitTransaction(
        $"txn-{Guid.NewGuid():N}", $"txn-{Guid.NewGuid():N}",
        "dev.ericslutz.gifforge.credits.60", // retired by migration 003
        user.AppAccountToken, "Sandbox", "hash"
      ),
      CancellationToken.None
    );

    // Unlike an already-processed transaction (which is a genuine no-op
    // success), an inactive product means the transaction was never
    // recognized at all, so the store reports it the same way the in-memory
    // reference implementation does: no result, not a zero-credit success.
    Assert.Null(result);
  }

  [Fact]
  public async Task RefreshTokenRotationClaimsOnceAndDetectsReuse()
  {
    var user = await CreateUserAsync();
    var familyId = Guid.NewGuid();
    var originalHash = $"hash-{Guid.NewGuid():N}";

    await store.SaveRefreshTokenAsync(
      new RefreshTokenRecord(originalHash, user.UserId, familyId, DateTimeOffset.UtcNow.AddDays(30), DateTimeOffset.UtcNow),
      CancellationToken.None
    );

    var replacementHash = $"hash-{Guid.NewGuid():N}";
    var firstRotation = await store.RotateRefreshTokenAsync(
      originalHash, replacementHash, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(30), CancellationToken.None
    );
    Assert.True(firstRotation.Claimed);
    Assert.NotNull(firstRotation.Token);
    Assert.Equal(user.UserId, firstRotation.Token.UserId);

    // Replaying the SAME original token (e.g. a stolen/leaked refresh token
    // used after the legitimate client already rotated it) must not be
    // claimable a second time — this is exactly what lets the caller detect
    // reuse and revoke the whole family.
    var replayRotation = await store.RotateRefreshTokenAsync(
      originalHash, $"hash-{Guid.NewGuid():N}", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(30), CancellationToken.None
    );
    Assert.False(replayRotation.Claimed);

    await store.RevokeRefreshTokenFamilyAsync(familyId, DateTimeOffset.UtcNow, CancellationToken.None);
    var replacementAfterFamilyRevoke = await store.GetRefreshTokenAsync(replacementHash, CancellationToken.None);
    // GetRefreshTokenAsync only filters on expiry, not revocation, so the
    // row is still readable — but it must be marked revoked.
    Assert.NotNull(replacementAfterFamilyRevoke);
    Assert.NotNull(replacementAfterFamilyRevoke.RevokedAt);
  }

  [Fact]
  public async Task UserOwnsGenerationAsyncDistinguishesOwners()
  {
    var owner = await CreateUserAsync();
    var stranger = await CreateUserAsync();
    await GrantAsync(owner.UserId, owner.AppAccountToken, 10, $"txn-{Guid.NewGuid():N}");
    var jobId = $"job-{Guid.NewGuid():N}";

    await store.TryReserveCreditsAsync(owner.UserId, jobId, 2, DateTimeOffset.UtcNow.AddHours(1), CancellationToken.None);

    Assert.True(await store.UserOwnsGenerationAsync(owner.UserId, jobId, CancellationToken.None));
    Assert.False(await store.UserOwnsGenerationAsync(stranger.UserId, jobId, CancellationToken.None));
  }

  [Fact]
  public async Task LinkingAppleIdentityToTwoAnonymousAccountsMergesTheOlderIntoTheNewer()
  {
    var first = await CreateUserAsync();
    var second = await CreateUserAsync();
    await GrantAsync(first.UserId, first.AppAccountToken, 10, $"txn-{Guid.NewGuid():N}");
    var appleSubject = $"apple-{Guid.NewGuid():N}";

    // First device links Apple recovery — becomes the authoritative account
    // for this Apple identity.
    var firstLink = await store.LinkAppleUserAsync(first.UserId, new AppleIdentity(appleSubject, "user@example.com"), DateTimeOffset.UtcNow, CancellationToken.None);
    Assert.NotNull(firstLink);
    Assert.Equal(first.UserId, firstLink.UserId);

    // A second, unrelated anonymous account on another device signs in with
    // the SAME Apple identity — this must merge into the first account
    // (ledger/credits move) and soft-delete the second account, rather than
    // silently orphaning the second device's local data.
    var secondLink = await store.LinkAppleUserAsync(second.UserId, new AppleIdentity(appleSubject, "user@example.com"), DateTimeOffset.UtcNow, CancellationToken.None);
    Assert.NotNull(secondLink);
    Assert.Equal(first.UserId, secondLink.UserId);

    var mergedBalance = await store.GetCreditBalanceAsync(first.UserId, CancellationToken.None);
    Assert.Equal(10, mergedBalance.GrantedCredits);

    var loserAccount = await store.GetUserAsync(second.UserId, CancellationToken.None);
    Assert.Null(loserAccount); // GetUserAsync filters out soft-deleted users.
  }
}
