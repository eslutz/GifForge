using System.Net;
using System.Net.Http.Json;
using GifForge.Backend.Providers;
using GifForge.Backend.Security;
using Microsoft.AspNetCore.Http;

namespace GifForge.Backend.Tests;

public sealed class ModelCostRefreshRouteTests
{
  [Fact]
  public async Task ManualRefreshRejectsUnauthenticatedOperator()
  {
    await using var app = GifForgeBackendApp.Create(
      provider: new FakeFrameSequenceProvider(),
      modelCostRefreshAuthorizer: new FixedAuthorizer(ModelCostRefreshAuthorizationResult.Unauthorized));
    var baseAddress = await BackendRouteTestHost.StartAsync(app);
    using var client = new HttpClient { BaseAddress = baseAddress };

    var response = await client.PostAsJsonAsync("/v1/operations/model-costs/refresh", new { provider = "fal.ai" });

    Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
  }

  [Fact]
  public async Task ManualRefreshRejectsOperatorWithoutRefreshRole()
  {
    await using var app = GifForgeBackendApp.Create(
      provider: new FakeFrameSequenceProvider(),
      modelCostRefreshAuthorizer: new FixedAuthorizer(ModelCostRefreshAuthorizationResult.Forbidden));
    var baseAddress = await BackendRouteTestHost.StartAsync(app);
    using var client = new HttpClient { BaseAddress = baseAddress };

    var response = await client.PostAsJsonAsync("/v1/operations/model-costs/refresh", new { provider = "fal.ai" });

    Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
  }

  private sealed class FixedAuthorizer(ModelCostRefreshAuthorizationResult result) : IModelCostRefreshAuthorizer
  {
    public Task<ModelCostRefreshAuthorizationResult> AuthorizeAsync(HttpContext context, CancellationToken cancellationToken) => Task.FromResult(result);
  }
}
