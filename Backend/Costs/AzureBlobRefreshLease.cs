using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Specialized;

namespace GifForge.Backend.Costs;

public interface IRefreshLease : IAsyncDisposable
{
  Task RenewAsync(CancellationToken cancellationToken);
}

public interface IRefreshLeaseFactory
{
  Task<IRefreshLease> AcquireAsync(string providerName, CancellationToken cancellationToken);
}

public sealed class AzureBlobRefreshLeaseFactory(BlobContainerClient container) : IRefreshLeaseFactory
{
  public async Task<IRefreshLease> AcquireAsync(string providerName, CancellationToken cancellationToken)
  {
    var blob = container.GetBlobClient($"model-cost-refresh-{Normalize(providerName)}.lock");
    try
    {
      await blob.UploadAsync(BinaryData.FromString("GifForge model cost refresh lock"), overwrite: false, cancellationToken);
    }
    catch (RequestFailedException error) when (error.Status == 409)
    {
    }

    for (var attempt = 0; attempt < 120; attempt++)
    {
      try
      {
        var lease = new BlobLeaseClient(blob);
        var response = await lease.AcquireAsync(TimeSpan.FromSeconds(60), cancellationToken: cancellationToken);
        return new ActiveRefreshLease(new BlobLeaseClient(blob, response.Value.LeaseId));
      }
      catch (RequestFailedException error) when (error.Status == 409)
      {
        await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
      }
    }

    throw new TimeoutException($"Timed out waiting for the model cost refresh lease for provider {providerName}.");
  }

  private static string Normalize(string providerName) =>
    new(providerName.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());

  private sealed class ActiveRefreshLease(BlobLeaseClient client) : IRefreshLease
  {
    public Task RenewAsync(CancellationToken cancellationToken) => client.RenewAsync(cancellationToken: cancellationToken);
    public async ValueTask DisposeAsync()
    {
      try { await client.ReleaseAsync(cancellationToken: CancellationToken.None); }
      catch (RequestFailedException error) when (error.Status is 404 or 409) { }
    }
  }
}
