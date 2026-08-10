using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace GifForge.Backend.Security;

public enum ModelCostRefreshAuthorizationResult
{
  Authorized,
  Unauthorized,
  Forbidden
}

public interface IModelCostRefreshAuthorizer
{
  Task<ModelCostRefreshAuthorizationResult> AuthorizeAsync(HttpContext context, CancellationToken cancellationToken);
}

public sealed class EntraModelCostRefreshAuthorizer(IConfiguration configuration) : IModelCostRefreshAuthorizer
{
  private readonly string? tenantId = configuration["GIFFORGE_MODEL_COST_REFRESH_TENANT_ID"];
  private readonly string? audience = configuration["GIFFORGE_MODEL_COST_REFRESH_AUDIENCE"];
  private readonly string requiredRole = configuration["GIFFORGE_MODEL_COST_REFRESH_ROLE"] ?? "gifforge.model-cost.refresh";
  private ConfigurationManager<OpenIdConnectConfiguration>? configurationManager;

  public async Task<ModelCostRefreshAuthorizationResult> AuthorizeAsync(HttpContext context, CancellationToken cancellationToken)
  {
    if (string.IsNullOrWhiteSpace(tenantId) || string.IsNullOrWhiteSpace(audience) ||
        !AuthenticationHeaderValue.TryParse(context.Request.Headers.Authorization.ToString(), out var header) ||
        !string.Equals(header.Scheme, "Bearer", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(header.Parameter))
    {
      return ModelCostRefreshAuthorizationResult.Unauthorized;
    }

    try
    {
      configurationManager ??= new ConfigurationManager<OpenIdConnectConfiguration>(
        $"https://login.microsoftonline.com/{Uri.EscapeDataString(tenantId)}/v2.0/.well-known/openid-configuration",
        new OpenIdConnectConfigurationRetriever(),
        new HttpDocumentRetriever { RequireHttps = true }
      );
      var metadata = await configurationManager.GetConfigurationAsync(cancellationToken);
      var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
      var principal = handler.ValidateToken(header.Parameter, new TokenValidationParameters
      {
        ValidateIssuerSigningKey = true,
        IssuerSigningKeys = metadata.SigningKeys,
        ValidateIssuer = true,
        ValidIssuers = [$"https://login.microsoftonline.com/{tenantId}/v2.0", $"https://sts.windows.net/{tenantId}/"],
        ValidateAudience = true,
        ValidAudience = audience,
        ValidateLifetime = true,
        ClockSkew = TimeSpan.FromMinutes(2)
      }, out _);

      return principal.Claims.Any(claim => claim.Type == "roles" && string.Equals(claim.Value, requiredRole, StringComparison.Ordinal))
        ? ModelCostRefreshAuthorizationResult.Authorized
        : ModelCostRefreshAuthorizationResult.Forbidden;
    }
    catch (SecurityTokenException)
    {
      return ModelCostRefreshAuthorizationResult.Unauthorized;
    }
    catch (InvalidOperationException)
    {
      return ModelCostRefreshAuthorizationResult.Unauthorized;
    }
    catch (HttpRequestException)
    {
      return ModelCostRefreshAuthorizationResult.Unauthorized;
    }
  }
}
