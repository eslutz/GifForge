namespace GifForge.CostUpdater;

public sealed record ModelCostUpdate(string AppConfigurationKey, decimal CostUsd);

public sealed record ProviderModelMapping(
  string ProviderName,
  string SourcePriceKey,
  string AppConfigurationKey,
  string Description
);

public sealed record CostUpdateSummary(
  int ProvidersChecked,
  int ProvidersSucceeded,
  int ProvidersFailed,
  int ValuesWritten
);
