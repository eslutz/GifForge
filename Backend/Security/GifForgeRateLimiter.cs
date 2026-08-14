using System.Collections.Concurrent;

namespace GifForge.Backend.Security;

public sealed class GifForgeRateLimiter
{
  private readonly AccountSecurityOptions options;
  private readonly ConcurrentDictionary<string, Bucket> buckets = new(StringComparer.Ordinal);

  public GifForgeRateLimiter(AccountSecurityOptions options)
  {
    this.options = options;
  }

  public RateLimitDecision CheckAuth(HttpContext context) =>
    Check(context, "auth", options.AuthRateLimitMax, null);

  public RateLimitDecision CheckAppAttest(HttpContext context) =>
    Check(context, "app-attest", options.AppAttestRateLimitMax, null);

  public RateLimitDecision CheckPurchase(HttpContext context, AuthenticatedUser user) =>
    Check(context, "purchase", options.PurchaseRateLimitMax, user.UserId.ToString("D"));

  public RateLimitDecision CheckGeneration(HttpContext context, AuthenticatedUser? user) =>
    Check(context, "generation", options.GenerationRateLimitMax, user?.UserId.ToString("D"));

  public RateLimitDecision CheckGenerationStatus(HttpContext context, AuthenticatedUser? user) =>
    Check(context, "generation-status", options.GenerationStatusRateLimitMax, user?.UserId.ToString("D"));

  private RateLimitDecision Check(
    HttpContext context,
    string area,
    int maxRequests,
    string? userId
  )
  {
    var now = DateTimeOffset.UtcNow;
    EvictExpiredBuckets(now);
    var retryAfter = TimeSpan.Zero;

    foreach (var key in Keys(context, area, userId))
    {
      var decision = Consume(key, maxRequests, options.RateLimitWindow, now);
      if (!decision.Allowed && decision.RetryAfter > retryAfter)
      {
        retryAfter = decision.RetryAfter;
      }
    }

    return retryAfter == TimeSpan.Zero
      ? RateLimitDecision.Pass
      : new RateLimitDecision(false, retryAfter);
  }

  private RateLimitDecision Consume(
    string key,
    int maxRequests,
    TimeSpan window,
    DateTimeOffset now
  )
  {
    while (true)
    {
      var bucket = buckets.GetOrAdd(key, _ => new Bucket(now.Add(window), 0));
      if (bucket.ResetAt <= now)
      {
        var reset = new Bucket(now.Add(window), 1);
        if (buckets.TryUpdate(key, reset, bucket))
        {
          return RateLimitDecision.Pass;
        }

        continue;
      }

      if (bucket.Count >= maxRequests)
      {
        return new RateLimitDecision(false, bucket.ResetAt - now);
      }

      var updated = bucket with { Count = bucket.Count + 1 };
      if (buckets.TryUpdate(key, updated, bucket))
      {
        return RateLimitDecision.Pass;
      }
    }
  }

  private static IEnumerable<string> Keys(HttpContext context, string area, string? userId)
  {
    yield return $"{area}:ip:{ClientAddress(context)}";

    if (!string.IsNullOrWhiteSpace(userId))
    {
      yield return $"{area}:user:{userId}";
    }

    var appAttestSession = context.Request.Headers["X-GifForge-App-Attest-Session"].ToString();
    if (!string.IsNullOrWhiteSpace(appAttestSession))
    {
      yield return $"{area}:app-attest:{SecurityTokenHelpers.Sha256Base64Url(appAttestSession)}";
    }
  }

  /// <summary>
  /// Behind Container Apps ingress the connection address is always the proxy, so
  /// every client shared one bucket. The ingress appends the real client address as
  /// the final X-Forwarded-For entry; earlier entries are client-supplied and
  /// untrusted, so only the last one is used.
  /// </summary>
  private static string ClientAddress(HttpContext context)
  {
    var forwardedFor = context.Request.Headers["X-Forwarded-For"].ToString();
    if (!string.IsNullOrWhiteSpace(forwardedFor))
    {
      var last = forwardedFor.Split(',')[^1].Trim();
      if (!string.IsNullOrWhiteSpace(last))
      {
        return last;
      }
    }

    return context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
  }

  private void EvictExpiredBuckets(DateTimeOffset now)
  {
    if (buckets.Count <= MaxTrackedBuckets)
    {
      return;
    }

    foreach (var entry in buckets)
    {
      if (entry.Value.ResetAt <= now)
      {
        buckets.TryRemove(entry.Key, out _);
      }
    }
  }

  private const int MaxTrackedBuckets = 10_000;

  private sealed record Bucket(DateTimeOffset ResetAt, int Count);
}

public sealed record RateLimitDecision(bool Allowed, TimeSpan RetryAfter)
{
  public static RateLimitDecision Pass { get; } = new(true, TimeSpan.Zero);
}
