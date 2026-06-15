using Microsoft.Extensions.Configuration;

namespace GifForge.Backend.Security;

public sealed record AppAttestOptions(
  bool Required,
  bool DemoBypassEnabled,
  string? AppIdentifier,
  string? RootCertificatePem
)
{
  public static AppAttestOptions FromConfiguration(IConfiguration configuration) =>
    new(
      string.Equals(
        configuration["GIFFORGE_APP_ATTEST_REQUIRED"],
        "true",
        StringComparison.OrdinalIgnoreCase
      ),
      string.Equals(
        configuration["GIFFORGE_APP_ATTEST_DEMO_BYPASS"],
        "true",
        StringComparison.OrdinalIgnoreCase
      ),
      configuration["GIFFORGE_APP_ATTEST_APP_IDENTIFIER"],
      RootCertificatePemFromConfiguration(configuration)
    );

  private static string? RootCertificatePemFromConfiguration(IConfiguration configuration)
  {
    var inlinePem = configuration["GIFFORGE_APP_ATTEST_ROOT_CERTIFICATE_PEM"];
    if (!string.IsNullOrWhiteSpace(inlinePem))
    {
      return inlinePem;
    }

    var pemPath = configuration["GIFFORGE_APP_ATTEST_ROOT_CERTIFICATE_PATH"];
    return string.IsNullOrWhiteSpace(pemPath)
      ? null
      : File.ReadAllText(pemPath);
  }
}
