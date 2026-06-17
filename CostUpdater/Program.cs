using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Identity;
using GifForge.CostUpdater;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
  .ConfigureAppConfiguration((_, configuration) =>
  {
    var builtConfiguration = configuration.Build();
    var keyVaultEndpoint = builtConfiguration["AZURE_KEY_VAULT_ENDPOINT"] ?? builtConfiguration["GIFFORGE_KEY_VAULT_URI"];
    if (string.IsNullOrWhiteSpace(keyVaultEndpoint))
    {
      return;
    }

    var managedIdentityClientId = builtConfiguration["AZURE_CLIENT_ID"];
    var credential = string.IsNullOrWhiteSpace(managedIdentityClientId)
      ? new DefaultAzureCredential()
      : new DefaultAzureCredential(new DefaultAzureCredentialOptions
      {
        ManagedIdentityClientId = managedIdentityClientId
      });

    configuration.AddAzureKeyVault(new Uri(keyVaultEndpoint), credential, new AzureKeyVaultConfigurationOptions());
  })
  .ConfigureFunctionsWorkerDefaults()
  .ConfigureServices(services =>
  {
    services.AddHttpClient(FalPricingSource.HttpClientName, client =>
    {
      client.BaseAddress = new Uri("https://api.fal.ai/");
    });

    services.AddHttpClient(LumaPricingSource.HttpClientName, client =>
    {
      client.BaseAddress = new Uri("https://lumalabs.ai/");
    });

    services.AddSingleton<ProviderPricingSource, FalPricingSource>();
    services.AddSingleton<ProviderPricingSource, LumaPricingSource>();
    services.AddSingleton(ProviderPricingRegistry.CreateDefault);
    services.AddSingleton<IAppConfigurationStore, AzureAppConfigurationStore>();
    services.AddSingleton<AppConfigurationCostWriter>();
    services.AddSingleton<ModelCostUpdater>();
  })
  .Build();

host.Run();
