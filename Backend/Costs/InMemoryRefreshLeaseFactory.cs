namespace GifForge.Backend.Costs;

/// <summary>
/// Local-dev fallback used when Azure Storage isn't configured.
/// AzureBlobRefreshLeaseFactory requires a real storage account to coordinate
/// the refresh lock across scaled instances; a single local process has no
/// concurrent instance to coordinate with, so the lease is a no-op.
/// </summary>
public sealed class InMemoryRefreshLeaseFactory : IRefreshLeaseFactory
{
  public Task<IRefreshLease> AcquireAsync(string providerName, CancellationToken cancellationToken) =>
    Task.FromResult<IRefreshLease>(NoopRefreshLease.Instance);

  private sealed class NoopRefreshLease : IRefreshLease
  {
    public static readonly NoopRefreshLease Instance = new();

    public Task RenewAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
  }
}
