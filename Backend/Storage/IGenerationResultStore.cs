using GifForge.Backend.Jobs;
using GifForge.Backend.Providers;

namespace GifForge.Backend.Storage;

public interface IGenerationResultStore
{
  Task<StoredGenerationResult> SaveAsync(
    string jobId,
    GeneratedMotionResult result,
    CancellationToken cancellationToken
  );

  Task<GeneratedMotionResult> ReadAsync(GenerationJob job, CancellationToken cancellationToken);
}

public sealed record StoredGenerationResult(string BlobName, string ContentType);
