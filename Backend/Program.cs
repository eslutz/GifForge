using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using Gifster.Backend.Jobs;
using Gifster.Backend.Models;
using Gifster.Backend.Providers;
using Gifster.Backend.Safety;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.AspNetCore.HttpOverrides;

if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ASPNETCORE_URLS")) &&
    string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ASPNETCORE_HTTP_PORTS")))
{
  Environment.SetEnvironmentVariable("ASPNETCORE_HTTP_PORTS", "8787");
}

var app = GifsterBackendApp.Create(args);
app.Run();

public static class GifsterBackendApp
{
  public static WebApplication Create(
    string[]? args = null,
    IGenerationProvider? provider = null,
    IJobStore? jobStore = null,
    string? publicBaseUrl = null
  )
  {
    var builder = WebApplication.CreateSlimBuilder(args ?? []);

    builder.Services.ConfigureHttpJsonOptions(ConfigureJson);
    builder.Services.AddSingleton(provider ?? new FakeFrameSequenceProvider());
    builder.Services.AddSingleton(jobStore ?? new MemoryJobStore());
    builder.Services.AddSingleton(new BackendOptions(
      publicBaseUrl ?? builder.Configuration["GIFSTER_PUBLIC_BASE_URL"]
    ));

    var app = builder.Build();
    app.UseForwardedHeaders(new ForwardedHeadersOptions
    {
      ForwardedHeaders = ForwardedHeaders.XForwardedHost | ForwardedHeaders.XForwardedProto
    });

    MapRoutes(app);
    return app;
  }

  private static void ConfigureJson(JsonOptions options)
  {
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, GifsterJsonSerializerContext.Default);
  }

  private static void MapRoutes(WebApplication app)
  {
    app.MapGet("/healthz", (IGenerationProvider provider) =>
      Json(new HealthResponse(true, provider.Name, "demo"), GifsterJsonSerializerContext.Default.HealthResponse));

    app.MapPost("/v1/generations", async (
      GenerationRequest request,
      HttpContext context,
      IGenerationProvider provider,
      IJobStore jobStore,
      BackendOptions options
    ) =>
    {
      var validation = ModerationPolicy.Validate(request);
      if (!validation.IsValid)
      {
        return Error(validation.StatusCode, validation.Message);
      }

      var providerJob = await provider.SubmitGenerationAsync(request, context.RequestAborted);
      var job = jobStore.Create(request, providerJob);
      var statusUrl = $"{RequestBaseUrl(context, options)}/v1/generations/{job.Id}";

      return Json(
        new JobSubmissionResponse(job.Id, "queued", statusUrl),
        GifsterJsonSerializerContext.Default.JobSubmissionResponse,
        statusCode: StatusCodes.Status202Accepted
      );
    });

    app.MapGet("/v1/generations/{jobId}", (
      string jobId,
      HttpContext context,
      IJobStore jobStore,
      BackendOptions options
    ) =>
    {
      if (!jobStore.TryGet(jobId, out var job))
      {
        return Error(StatusCodes.Status404NotFound, "Generation job was not found.");
      }

      var status = jobStore.StatusFor(job);
      var downloadUrl = status == GenerationJobStatus.Succeeded
        ? $"{RequestBaseUrl(context, options)}/v1/generations/{job.Id}/result"
        : null;

      return Json(
        new JobStatusResponse(job.Id, status.JsonValue(), downloadUrl, status == GenerationJobStatus.Failed ? job.FailedMessage : null),
        GifsterJsonSerializerContext.Default.JobStatusResponse
      );
    });

    app.MapGet("/v1/generations/{jobId}/result", async (
      string jobId,
      IGenerationProvider provider,
      IJobStore jobStore,
      CancellationToken cancellationToken
    ) =>
    {
      if (!jobStore.TryGet(jobId, out var job))
      {
        return Error(StatusCodes.Status404NotFound, "Generation job was not found.");
      }

      if (jobStore.StatusFor(job) != GenerationJobStatus.Succeeded)
      {
        return Error(StatusCodes.Status409Conflict, "Generation result is not ready.");
      }

      var result = await provider.GetResultAsync(job.Request, cancellationToken);
      return Json(
        result,
        GifsterJsonSerializerContext.Default.FrameSequenceAsset,
        contentType: "application/vnd.gifster.frame-sequence+json"
      );
    });
  }

  private static IResult Json<T>(T value, JsonTypeInfo<T> jsonTypeInfo, int? statusCode = null, string? contentType = null) =>
    Results.Json(value, jsonTypeInfo, contentType: contentType, statusCode: statusCode);

  private static IResult Error(int statusCode, string message) =>
    Json(
      new ErrorResponse(statusCode >= 500 ? "internal_error" : "invalid_request", message),
      GifsterJsonSerializerContext.Default.ErrorResponse,
      statusCode: statusCode
    );

  private static string RequestBaseUrl(HttpContext context, BackendOptions options)
  {
    if (!string.IsNullOrWhiteSpace(options.PublicBaseUrl))
    {
      return options.PublicBaseUrl.TrimEnd('/');
    }

    return $"{context.Request.Scheme}://{context.Request.Host}";
  }
}

public sealed record BackendOptions(string? PublicBaseUrl);

[JsonSerializable(typeof(HealthResponse))]
[JsonSerializable(typeof(ErrorResponse))]
[JsonSerializable(typeof(GenerationRequest))]
[JsonSerializable(typeof(JobSubmissionResponse))]
[JsonSerializable(typeof(JobStatusResponse))]
[JsonSerializable(typeof(FrameSequenceAsset))]
[JsonSerializable(typeof(FrameSpec))]
internal partial class GifsterJsonSerializerContext : JsonSerializerContext;

public sealed record HealthResponse(bool Ok, string Provider, string Mode);
public sealed record ErrorResponse(string Error, string Message);

public sealed record JobSubmissionResponse(string JobId, string Status, string StatusUrl);
public sealed record JobStatusResponse(string JobId, string Status, string? DownloadUrl, string? Message);
