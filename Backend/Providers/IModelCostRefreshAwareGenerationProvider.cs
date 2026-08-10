using GifForge.Backend.Models;

namespace GifForge.Backend.Providers;

public interface IModelCostRefreshAwareGenerationProvider
{
  Task EnsureModelCostsFreshAsync(
    GenerationRequest request,
    IReadOnlySet<string> attemptedProviders,
    IReadOnlySet<string> attemptedModelIds,
    CancellationToken cancellationToken
  );
}
