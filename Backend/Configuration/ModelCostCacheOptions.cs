using System.Globalization;

namespace GifForge.Backend.Configuration;

public sealed record ModelCostCacheOptions(TimeSpan Ttl)
{
  public static readonly TimeSpan DefaultTtl = TimeSpan.FromDays(1);

  public static ModelCostCacheOptions FromConfiguration(IConfiguration configuration)
  {
    var raw = configuration["GIFFORGE_MODEL_COST_CACHE_TTL"];
    return TimeSpan.TryParse(raw, CultureInfo.InvariantCulture, out var ttl) && ttl > TimeSpan.Zero
      ? new(ttl)
      : new(DefaultTtl);
  }
}
