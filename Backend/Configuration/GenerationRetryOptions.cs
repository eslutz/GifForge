using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Configuration;

public sealed record GenerationRetryOptions(int MaxAttempts)
{
  public static GenerationRetryOptions Default { get; } = new(3);

  public static GenerationRetryOptions FromConfiguration(IConfiguration configuration) =>
    new(
      int.TryParse(configuration["GIFFORGE_GENERATION_MAX_ATTEMPTS"], out var maxAttempts) &&
      maxAttempts is >= 1 and <= 5
        ? maxAttempts
        : Default.MaxAttempts
    );
}
