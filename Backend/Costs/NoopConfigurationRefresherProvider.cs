using Microsoft.Extensions.Configuration.AzureAppConfiguration;

namespace GifForge.Backend.Costs;

public sealed class NoopConfigurationRefresherProvider : IConfigurationRefresherProvider
{
  public IEnumerable<IConfigurationRefresher> Refreshers => [];
}
