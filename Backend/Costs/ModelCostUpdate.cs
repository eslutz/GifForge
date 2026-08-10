namespace GifForge.Backend.Costs;

public sealed record ModelCostUpdate(string AppConfigurationKey, decimal CostUsd);

public sealed record ProviderModelMapping(
  string ProviderName,
  string SourcePriceKey,
  string AppConfigurationKey,
  string Description
);

public sealed record ProviderRefreshResult(
  string ProviderName,
  bool Succeeded,
  bool UsedStaleCache,
  int ValuesWritten,
  DateTimeOffset? LastSuccessfulRefreshAtUtc,
  string? ErrorMessage
);
