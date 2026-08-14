using System.Collections.Concurrent;

namespace GifForge.Backend.Jobs;

/// <summary>
/// Serializes concurrent work sharing the same key (e.g. two requests racing
/// on the same idempotency key) without blocking work on unrelated keys.
/// Entries are removed once their last waiter releases, so long-running
/// processes never accumulate one semaphore per historical key.
/// </summary>
public sealed class KeyedAsyncLock
{
  private readonly ConcurrentDictionary<string, Entry> entries = new();

  public async Task<IAsyncDisposable> AcquireAsync(string key, CancellationToken cancellationToken)
  {
    Entry entry;
    lock (entries)
    {
      entry = entries.AddOrUpdate(
        key,
        static _ => new Entry(),
        static (_, existing) =>
        {
          existing.Waiters++;
          return existing;
        }
      );
    }

    await entry.Semaphore.WaitAsync(cancellationToken).ConfigureAwait(false);
    return new Releaser(this, key, entry);
  }

  private void Release(string key, Entry entry)
  {
    entry.Semaphore.Release();
    lock (entries)
    {
      if (--entry.Waiters == 0)
      {
        entries.TryRemove(key, out _);
        entry.Semaphore.Dispose();
      }
    }
  }

  private sealed class Entry
  {
    public SemaphoreSlim Semaphore { get; } = new(1, 1);
    public int Waiters = 1;
  }

  private sealed class Releaser(KeyedAsyncLock owner, string key, Entry entry) : IAsyncDisposable
  {
    private int released;

    public ValueTask DisposeAsync()
    {
      if (Interlocked.Exchange(ref released, 1) == 0)
      {
        owner.Release(key, entry);
      }
      return ValueTask.CompletedTask;
    }
  }
}
