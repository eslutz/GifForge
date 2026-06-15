using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Providers;

public sealed record ExternalHttpProviderOptions(
  string Name,
  Uri SubmitUrl,
  string ResultUrlTemplate,
  string? AuthorizationHeader
)
{
  public static ExternalHttpProviderOptions FromConfiguration(IConfiguration configuration)
  {
    var submitUrl = configuration["GIFFORGE_EXTERNAL_PROVIDER_SUBMIT_URL"];
    var resultUrlTemplate = configuration["GIFFORGE_EXTERNAL_PROVIDER_RESULT_URL_TEMPLATE"];
    if (string.IsNullOrWhiteSpace(submitUrl) || string.IsNullOrWhiteSpace(resultUrlTemplate))
    {
      throw new InvalidOperationException(
        "External HTTP provider requires GIFFORGE_EXTERNAL_PROVIDER_SUBMIT_URL and GIFFORGE_EXTERNAL_PROVIDER_RESULT_URL_TEMPLATE."
      );
    }

    return new ExternalHttpProviderOptions(
      configuration["GIFFORGE_EXTERNAL_PROVIDER_NAME"] ?? "external-http",
      new Uri(submitUrl),
      resultUrlTemplate,
      configuration["GIFFORGE_EXTERNAL_PROVIDER_AUTHORIZATION"]
    );
  }
}
