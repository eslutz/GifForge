using System.Diagnostics.CodeAnalysis;
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Data.Tables;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using Azure.Storage.Queues.Models;
using DotNetEnv;
using GifForge.Backend.Configuration;
using GifForge.Backend.Costs;
using GifForge.Backend.Jobs;
using GifForge.Backend.Models;
using GifForge.Backend.Operations;
using GifForge.Backend.Providers;
using GifForge.Backend.Queueing;
using GifForge.Backend.Safety;
using GifForge.Backend.Security;
using GifForge.Backend.Storage;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Configuration.AzureAppConfiguration;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

// Local-dev-only convenience: deployed environments (Container Apps) never
// have this file and set real environment variables instead, so a missing
// file here is expected and silently skipped rather than treated as an error.
var envFilePath = Path.Combine(Directory.GetCurrentDirectory(), ".env");
if (File.Exists(envFilePath))
{
  Env.Load(envFilePath);
}

if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ASPNETCORE_URLS")) &&
    string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ASPNETCORE_HTTP_PORTS")))
{
  Environment.SetEnvironmentVariable("ASPNETCORE_HTTP_PORTS", "8787");
}

var app = GifForgeBackendApp.Create(args);
app.Run();

public static class GifForgeBackendApp
{
  public static WebApplication Create(
    string[]? args = null,
    IGenerationProvider? provider = null,
    IJobStore? jobStore = null,
    IGenerationJobDispatcher? jobDispatcher = null,
    IAppAttestVerifier? appAttestVerifier = null,
    string? publicBaseUrl = null,
    IAppAttestStateStore? appAttestStateStore = null,
    IGenerationEventSink? generationEventSink = null,
    AccountSecurityService? accountSecurity = null,
    IModelCostRefreshAuthorizer? modelCostRefreshAuthorizer = null
  )
  {
    var builder = WebApplication.CreateSlimBuilder(args ?? []);
    ConfigureAzureConfiguration(builder);
    ConfigureOpenTelemetry(builder);

    // Kestrel's 30MB default silently rejected payloads the moderation policy is
    // documented to accept (up to 50MB decoded media as base64 JSON).
    builder.WebHost.ConfigureKestrel(kestrel => kestrel.Limits.MaxRequestBodySize = 100_000_000);

    builder.Services.ConfigureHttpJsonOptions(ConfigureJson);
    builder.Services.AddSingleton(BackendLogContext.FromConfiguration(builder.Configuration));
    var retentionOptions = GenerationRetentionOptions.FromConfiguration(builder.Configuration);
    builder.Services.AddSingleton(retentionOptions);
    builder.Services.AddSingleton(GenerationRetryOptions.FromConfiguration(builder.Configuration));
    if (provider is not null)
    {
      builder.Services.AddSingleton<IGenerationProvider>(provider);
    }
    else
    {
      _ = ConfiguredGenerationProvider.CreateRoutedVideoProvider(builder.Configuration);
      builder.Services.AddSingleton<IGenerationProvider>(serviceProvider =>
        new ConfiguredGenerationProvider(
          builder.Configuration,
          ConfiguredGenerationProvider.CreateRoutedVideoProvider,
          () => serviceProvider.GetRequiredService<ModelCostRefreshCoordinator>()
        ));
    }
    builder.Services.AddSingleton(jobStore ?? CreateJobStore(builder.Configuration, retentionOptions));
    ConfigureJobDispatch(builder, jobDispatcher);
    if (generationEventSink is null)
    {
      builder.Services.AddSingleton<IGenerationEventSink, LoggingGenerationEventSink>();
    }
    else
    {
      builder.Services.AddSingleton(generationEventSink);
    }
    builder.Services.AddSingleton(CreateResultStore(builder.Configuration));
    var appAttestOptions = AppAttestOptions.FromConfiguration(builder.Configuration);
    builder.Services.AddSingleton<IAppAttestService>(
      new AppAttestService(
        appAttestOptions,
        appAttestVerifier ?? CreateAppAttestVerifier(appAttestOptions),
        appAttestStateStore ?? CreateAppAttestStateStore(builder.Configuration)
      )
    );
    if (accountSecurity is null)
    {
      builder.Services.AddSingleton(serviceProvider =>
        CreateAccountSecurityService(
          builder.Configuration,
          serviceProvider.GetRequiredService<ILogger<AccountSecurityService>>()
        )
      );
    }
    else
    {
      builder.Services.AddSingleton(accountSecurity);
    }
    builder.Services.AddSingleton(new GifForgeRateLimiter(AccountSecurityOptions.FromConfiguration(builder.Configuration)));
    builder.Services.AddSingleton<KeyedAsyncLock>();
    ConfigureWorkerServices(builder);
    ConfigureRetentionCleanup(builder, retentionOptions);
    builder.Services.AddSingleton(new BackendOptions(
      publicBaseUrl ?? ResolvePublicBaseUrl(builder.Configuration)
    ));
    ConfigureModelCostServices(builder);
    builder.Services.AddSingleton<IModelCostRefreshAuthorizer>(modelCostRefreshAuthorizer ?? new EntraModelCostRefreshAuthorizer(builder.Configuration));

    var app = builder.Build();
    if (!string.IsNullOrWhiteSpace(app.Configuration["AZURE_APP_CONFIG_ENDPOINT"]))
    {
      app.UseAzureAppConfiguration();
    }

    // Forwarded headers are deliberately NOT honored: with no trusted-proxy list,
    // any client could spoof X-Forwarded-Host and control the statusUrl/downloadUrl
    // returned by the API. Deployed environments resolve their public base URL from
    // configuration or the Container Apps environment instead (ResolvePublicBaseUrl).
    UseBackendLogScope(app);

    MapRoutes(app);
    return app;
  }

  /// <summary>
  /// Resolves the base URL used in returned status/download links: explicit
  /// configuration first, then the Azure Container Apps ingress FQDN derived from
  /// the environment variables Container Apps injects into every replica.
  /// </summary>
  private static string? ResolvePublicBaseUrl(IConfiguration configuration)
  {
    var configured = configuration["GIFFORGE_PUBLIC_BASE_URL"];
    if (!string.IsNullOrWhiteSpace(configured))
    {
      return configured;
    }

    var containerAppName = configuration["CONTAINER_APP_NAME"];
    var containerAppDomain = configuration["CONTAINER_APP_ENV_DNS_SUFFIX"];
    if (!string.IsNullOrWhiteSpace(containerAppName) && !string.IsNullOrWhiteSpace(containerAppDomain))
    {
      return $"https://{containerAppName}.{containerAppDomain}";
    }

    return null;
  }

  private static void UseBackendLogScope(WebApplication app)
  {
    var logContext = app.Services.GetRequiredService<BackendLogContext>();
    app.Use(async (context, next) =>
    {
      var loggerFactory = context.RequestServices.GetRequiredService<ILoggerFactory>();
      var logger = loggerFactory.CreateLogger("GifForge.Backend.Request");
      using (logger.BeginScope(logContext.ToScope()))
      {
        await next();
      }
    });
  }

  private static void ConfigureJson(JsonOptions options)
  {
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, GifForgeJsonSerializerContext.Default);
  }

  private static void ConfigureModelCostServices(WebApplicationBuilder builder)
  {
    if (string.IsNullOrWhiteSpace(builder.Configuration["AZURE_APP_CONFIG_ENDPOINT"]))
    {
      builder.Services.AddSingleton<IConfigurationRefresherProvider, NoopConfigurationRefresherProvider>();
    }
    builder.Services.AddHttpClient(FalPricingSource.HttpClientName, client => client.BaseAddress = new Uri("https://api.fal.ai/"));
    builder.Services.AddHttpClient(LumaPricingSource.HttpClientName, client => client.BaseAddress = new Uri("https://lumalabs.ai/"));
    builder.Services.AddSingleton<ProviderPricingSource, FalPricingSource>();
    builder.Services.AddSingleton<ProviderPricingSource, LumaPricingSource>();
    builder.Services.AddSingleton(ProviderPricingRegistry.CreateDefault);
    if (string.IsNullOrWhiteSpace(builder.Configuration["AZURE_APP_CONFIG_ENDPOINT"]))
    {
      builder.Services.AddSingleton<IAppConfigurationCostStore, InMemoryAppConfigurationCostStore>();
    }
    else
    {
      builder.Services.AddSingleton<IAppConfigurationCostStore, AzureAppConfigurationCostStore>();
    }
    builder.Services.AddSingleton<AppConfigurationCostWriter>();
    builder.Services.AddSingleton<IRefreshLeaseFactory>(serviceProvider => CreateRefreshLeaseFactory(builder.Configuration));
    builder.Services.AddSingleton(ModelCostCacheOptions.FromConfiguration(builder.Configuration));
    builder.Services.AddSingleton<ModelCostRefreshCoordinator>();
  }

  private static IRefreshLeaseFactory CreateRefreshLeaseFactory(IConfiguration configuration)
  {
    var storage = BackendStorageOptions.FromConfiguration(configuration);
    if (!storage.IsConfigured) return new InMemoryRefreshLeaseFactory();
    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = storage.ManagedIdentityClientId });
    var endpoint = new Uri($"https://{storage.StorageAccountName}.blob.core.windows.net");
    return new AzureBlobRefreshLeaseFactory(new BlobServiceClient(endpoint, credential).GetBlobContainerClient(storage.ControlContainerName));
  }

  private static void ConfigureAzureConfiguration(WebApplicationBuilder builder)
  {
    var managedIdentityClientId = builder.Configuration["AZURE_CLIENT_ID"];
    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
      ManagedIdentityClientId = string.IsNullOrWhiteSpace(managedIdentityClientId) ? null : managedIdentityClientId
    });

    var appConfigEndpoint = builder.Configuration["AZURE_APP_CONFIG_ENDPOINT"];
    if (!string.IsNullOrWhiteSpace(appConfigEndpoint))
    {
      builder.Configuration.AddAzureAppConfiguration(options =>
      {
        options.Connect(new Uri(appConfigEndpoint), credential)
          .ConfigureRefresh(refresh => refresh.RegisterAll())
          .ConfigureKeyVault(keyVault => keyVault.SetCredential(credential));
      });
      builder.Services.AddAzureAppConfiguration();
    }

    var keyVaultEndpoint = builder.Configuration["AZURE_KEY_VAULT_ENDPOINT"] ?? builder.Configuration["GIFFORGE_KEY_VAULT_URI"];
    if (!string.IsNullOrWhiteSpace(keyVaultEndpoint))
    {
      builder.Configuration.AddAzureKeyVault(
        new SecretClient(new Uri(keyVaultEndpoint), credential),
        new KeyVaultSecretManager()
      );
    }
  }

  private static void ConfigureOpenTelemetry(WebApplicationBuilder builder)
  {
    var serviceName = builder.Configuration["OTEL_SERVICE_NAME"] ?? "GifForge.Backend";
    var openTelemetry = builder.Services.AddOpenTelemetry()
      .ConfigureResource(resource => resource.AddService(serviceName));

    openTelemetry.WithTracing(tracing =>
    {
      tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation();
      if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
      {
        tracing.AddOtlpExporter();
      }
    });

    openTelemetry.WithMetrics(metrics =>
    {
      metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation();
      if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
      {
        metrics.AddOtlpExporter();
      }
    });
  }

  private static IJobStore CreateJobStore(
    IConfiguration configuration,
    GenerationRetentionOptions retentionOptions
  )
  {
    var storage = BackendStorageOptions.FromConfiguration(configuration);
    if (!storage.IsConfigured)
    {
      return new MemoryJobStore(retentionOptions.JobLifetime);
    }

    PreserveAzureTableEntityConstructors();

    var credentialOptions = new DefaultAzureCredentialOptions
    {
      ManagedIdentityClientId = storage.ManagedIdentityClientId
    };
    var credential = new DefaultAzureCredential(credentialOptions);
    var tableEndpoint = new Uri($"https://{storage.StorageAccountName}.table.core.windows.net");
    var tableClient = new TableClient(tableEndpoint, storage.JobsTableName, credential);

    return new TableGenerationJobStore(new AzureGenerationJobTable(tableClient), retentionOptions.JobLifetime);
  }

  [DynamicDependency(DynamicallyAccessedMemberTypes.PublicConstructors, typeof(TableEntity))]
  private static void PreserveAzureTableEntityConstructors()
  {
  }

  private static IGenerationResultStore CreateResultStore(IConfiguration configuration)
  {
    var storage = BackendStorageOptions.FromConfiguration(configuration);
    if (!storage.IsConfigured)
    {
      return new MemoryGenerationResultStore();
    }

    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
      ManagedIdentityClientId = storage.ManagedIdentityClientId
    });
    var blobEndpoint = new Uri($"https://{storage.StorageAccountName}.blob.core.windows.net");
    var serviceClient = new BlobServiceClient(blobEndpoint, credential);
    return new AzureBlobGenerationResultStore(serviceClient.GetBlobContainerClient(storage.ResultsContainerName));
  }

  private static void ConfigureJobDispatch(WebApplicationBuilder builder, IGenerationJobDispatcher? jobDispatcher)
  {
    if (jobDispatcher is not null)
    {
      builder.Services.AddSingleton(jobDispatcher);
      return;
    }

    var storage = BackendStorageOptions.FromConfiguration(builder.Configuration);
    if (storage.IsConfigured)
    {
      builder.Services.AddSingleton(CreateAzureJobDispatcher(storage));
      return;
    }

    // Local-dev fallback: without Azure Storage there is no separate queue
    // worker app to process jobs, so a submitted generation would otherwise sit
    // "queued" forever behind NoopGenerationJobDispatcher. Run the same
    // GenerationWorker logic in-process against an in-memory queue instead.
    var localQueue = new InProcessGenerationJobQueue();
    builder.Services.AddSingleton<IGenerationJobDispatcher>(localQueue);
    builder.Services.AddSingleton<IGenerationJobQueueReader>(localQueue);
    builder.Services.AddSingleton(GenerationQueueOptions.Default);
    builder.Services.AddSingleton(serviceProvider => new GenerationWorker(
      serviceProvider.GetRequiredService<IJobStore>(),
      serviceProvider.GetRequiredService<IGenerationProvider>(),
      serviceProvider.GetRequiredService<IGenerationResultStore>(),
      serviceProvider.GetRequiredService<IGenerationEventSink>(),
      serviceProvider.GetRequiredService<AccountSecurityService>(),
      serviceProvider.GetService<IConfigurationRefresherProvider>()
    ));
    builder.Services.AddHostedService<GenerationQueueWorkerService>();
  }

  private static AzureQueueGenerationJobDispatcher CreateAzureJobDispatcher(BackendStorageOptions storage)
  {
    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
      ManagedIdentityClientId = storage.ManagedIdentityClientId
    });
    var queueUri = new Uri(
      $"https://{storage.StorageAccountName}.queue.core.windows.net/{storage.GenerationQueueName}"
    );
    var queueClient = new QueueClient(
      queueUri,
      credential,
      new QueueClientOptions
      {
        MessageEncoding = QueueMessageEncoding.Base64
      }
    );

    return new AzureQueueGenerationJobDispatcher(queueClient);
  }

  private static IAppAttestStateStore CreateAppAttestStateStore(IConfiguration configuration)
  {
    var storage = BackendStorageOptions.FromConfiguration(configuration);
    if (!storage.IsConfigured)
    {
      return new MemoryAppAttestStateStore();
    }

    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
      ManagedIdentityClientId = storage.ManagedIdentityClientId
    });
    var tableEndpoint = new Uri($"https://{storage.StorageAccountName}.table.core.windows.net");
    var tableClient = new TableClient(tableEndpoint, storage.AppAttestStateTableName, credential);

    return new AzureTableAppAttestStateStore(tableClient);
  }

  private static IAppAttestVerifier CreateAppAttestVerifier(AppAttestOptions options)
  {
    if (options.AppIdentifiers.Count == 0 ||
        string.IsNullOrWhiteSpace(options.RootCertificatePem))
    {
      return new UnavailableAppAttestVerifier();
    }

    try
    {
      var rootCertificate = X509Certificate2.CreateFromPem(options.RootCertificatePem);
      return new AppleAppAttestVerifier(options.AppIdentifiers, rootCertificate);
    }
    catch (Exception error) when (
      error is CryptographicException or ArgumentException or InvalidOperationException
    )
    {
      return new UnavailableAppAttestVerifier();
    }
  }

  private static AccountSecurityService CreateAccountSecurityService(
    IConfiguration configuration,
    ILogger<AccountSecurityService> logger
  )
  {
    var options = AccountSecurityOptions.FromConfiguration(configuration);
    var tokenService = new BackendTokenService(options);
    var appleValidator = new AppleIdentityTokenValidator(options, new HttpClient());
    var transactionVerifier = new StoreKitJwsTransactionVerifier(options);
    var notificationVerifier = new AppStoreServerNotificationJwsVerifier(options);
    var signInWithAppleNotificationVerifier = new SignInWithAppleNotificationJwtVerifier(options, new HttpClient());

    return new AccountSecurityService(
      options,
      appleValidator,
      transactionVerifier,
      notificationVerifier,
      signInWithAppleNotificationVerifier,
      tokenService,
      CreateAccountStore(configuration),
      logger
    );
  }

  private static IGifForgeAccountStore CreateAccountStore(IConfiguration configuration)
  {
    var sqlServer = configuration["GIFFORGE_SQL_SERVER"];
    var sqlDatabase = configuration["GIFFORGE_SQL_DATABASE"];
    var managedIdentityClientId = configuration["AZURE_CLIENT_ID"];
    return !string.IsNullOrWhiteSpace(sqlServer) && !string.IsNullOrWhiteSpace(sqlDatabase)
      ? new SqlGifForgeAccountStore(sqlServer, sqlDatabase, managedIdentityClientId)
      : new MemoryGifForgeAccountStore();
  }

  private static void ConfigureWorkerServices(WebApplicationBuilder builder)
  {
    if (!string.Equals(builder.Configuration["GIFFORGE_WORKER_ENABLED"], "true", StringComparison.OrdinalIgnoreCase))
    {
      return;
    }

    var storage = BackendStorageOptions.FromConfiguration(builder.Configuration);
    if (!storage.IsConfigured)
    {
      throw new InvalidOperationException("GIFFORGE_WORKER_ENABLED requires GIFFORGE_STORAGE_ACCOUNT_NAME.");
    }

    var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
      ManagedIdentityClientId = storage.ManagedIdentityClientId
    });
    var queueUri = new Uri(
      $"https://{storage.StorageAccountName}.queue.core.windows.net/{storage.GenerationQueueName}"
    );
    var queueClient = new QueueClient(
      queueUri,
      credential,
      new QueueClientOptions
      {
        MessageEncoding = QueueMessageEncoding.Base64
      }
    );

    var queueOptions = GenerationQueueOptions.FromConfiguration(builder.Configuration);
    builder.Services.AddSingleton(queueOptions);
    builder.Services.AddSingleton<IGenerationJobQueueReader>(new AzureQueueGenerationJobReader(queueClient, queueOptions));
    builder.Services.AddSingleton(serviceProvider => new GenerationWorker(
      serviceProvider.GetRequiredService<IJobStore>(),
      serviceProvider.GetRequiredService<IGenerationProvider>(),
      serviceProvider.GetRequiredService<IGenerationResultStore>(),
      serviceProvider.GetRequiredService<IGenerationEventSink>(),
      serviceProvider.GetRequiredService<AccountSecurityService>(),
      serviceProvider.GetService<IConfigurationRefresherProvider>()
    ));
    builder.Services.AddHostedService<GenerationQueueWorkerService>();
  }

  private static void ConfigureRetentionCleanup(
    WebApplicationBuilder builder,
    GenerationRetentionOptions retentionOptions
  )
  {
    if (!retentionOptions.CleanupEnabled)
    {
      return;
    }

    builder.Services.AddHostedService<GenerationRetentionCleanupService>();
  }

  private static void MapRoutes(WebApplication app)
  {
    app.MapGet("/health", (IGenerationProvider provider) =>
      Json(new HealthResponse(true, provider.Name, provider.Mode), GifForgeJsonSerializerContext.Default.HealthResponse));

    // Readiness actually exercises the job store (Table Storage or memory) so a
    // replica that cannot reach its dependencies drops out of rotation instead of
    // surfacing storage outages as user-facing errors.
    app.MapGet("/health/ready", async (IGenerationProvider provider, IJobStore jobStore, CancellationToken cancellationToken) =>
    {
      try
      {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));
        _ = await jobStore.GetAsync("health-readiness-probe", timeout.Token);
        return Json(new HealthResponse(true, provider.Name, provider.Mode), GifForgeJsonSerializerContext.Default.HealthResponse);
      }
      catch (Exception error) when (error is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
      {
        return Error(StatusCodes.Status503ServiceUnavailable, "A backend dependency is unavailable.");
      }
    });

    app.MapPost("/v1/operations/model-costs/refresh", async (
      ModelCostRefreshRequest? request,
      IModelCostRefreshAuthorizer authorizer,
      IServiceProvider services,
      HttpContext context
    ) =>
    {
      var authorization = await authorizer.AuthorizeAsync(context, context.RequestAborted);
      if (authorization == ModelCostRefreshAuthorizationResult.Unauthorized)
      {
        return Error(StatusCodes.Status401Unauthorized, "A valid operator identity is required.");
      }
      if (authorization == ModelCostRefreshAuthorizationResult.Forbidden)
      {
        return Error(StatusCodes.Status403Forbidden, "The operator identity is not authorized to refresh model costs.");
      }

      try
      {
        var coordinator = services.GetRequiredService<ModelCostRefreshCoordinator>();
        var results = string.IsNullOrWhiteSpace(request?.Provider)
          ? await coordinator.RefreshAllAsync(context.RequestAborted)
          : [await coordinator.RefreshProviderAsync(request.Provider, context.RequestAborted)];
        return Json(
          new ModelCostRefreshResponse(results.Select(result => new ModelCostRefreshProviderResponse(
            result.ProviderName,
            result.Succeeded,
            result.UsedStaleCache,
            result.ValuesWritten,
            result.LastSuccessfulRefreshAtUtc,
            result.Succeeded ? null : result.ErrorMessage
          )).ToArray()),
          GifForgeJsonSerializerContext.Default.ModelCostRefreshResponse
        );
      }
      catch (ArgumentException)
      {
        return Error(StatusCodes.Status400BadRequest, "The requested model cost provider is not supported.");
      }
    });

    app.MapPost("/v1/app-attest/challenges", async (
      IAppAttestService appAttest,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAppAttest(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      return Json(
        await appAttest.CreateChallengeAsync(context.RequestAborted),
        GifForgeJsonSerializerContext.Default.AppAttestChallengeResponse
      );
    });

    app.MapPost("/v1/app-attest/attestations", async (
      AppAttestAttestationRequest request,
      IAppAttestService appAttest,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAppAttest(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      var session = await appAttest.CreateSessionAsync(request, context.RequestAborted);
      return session is null
        ? Error(StatusCodes.Status401Unauthorized, "App Attest challenge could not be verified.")
        : Json(session, GifForgeJsonSerializerContext.Default.AppAttestSessionResponse);
    });

    app.MapPost("/v1/auth/apple", async (
      AppleAuthRequest request,
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAuth(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      var session = await accountSecurity.SignInWithAppleAsync(request, context.RequestAborted);
      return session is null
        ? Error(StatusCodes.Status401Unauthorized, "Authentication failed.")
        : Json(session, GifForgeJsonSerializerContext.Default.AuthTokenResponse);
    });

    app.MapPost("/v1/auth/anonymous", async (
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAuth(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      return Json(
        await accountSecurity.CreateAnonymousSessionAsync(context.RequestAborted),
        GifForgeJsonSerializerContext.Default.AuthTokenResponse
      );
    });

    app.MapPost("/v1/auth/apple/link", async (
      AppleAuthRequest request,
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var user = accountSecurity.Authenticate(context);
      if (user is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAuth(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      var session = await accountSecurity.LinkSignInWithAppleAsync(user, request, context.RequestAborted);
      return session is null
        ? Error(StatusCodes.Status401Unauthorized, "Apple recovery could not be enabled.")
        : Json(session, GifForgeJsonSerializerContext.Default.AuthTokenResponse);
    });

    app.MapPost("/v1/auth/refresh", async (
      RefreshTokenRequest request,
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAuth(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      var session = await accountSecurity.RefreshAsync(request, context.RequestAborted);
      return session is null
        ? Error(StatusCodes.Status401Unauthorized, "Authentication failed.")
        : Json(session, GifForgeJsonSerializerContext.Default.AuthTokenResponse);
    });

    app.MapPost("/v1/auth/logout", async (
      LogoutRequest request,
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAuth(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      await accountSecurity.LogoutAsync(request, context.RequestAborted);
      return Results.NoContent();
    });

    app.MapGet("/v1/me", async (
      AccountSecurityService accountSecurity,
      HttpContext context
    ) =>
    {
      var user = accountSecurity.Authenticate(context);
      if (user is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var profile = await accountSecurity.ProfileAsync(user, context.RequestAborted);
      return profile is null
        ? Error(StatusCodes.Status401Unauthorized, "Authentication is required.")
        : Json(profile, GifForgeJsonSerializerContext.Default.MeResponse);
    });

    app.MapGet("/v1/me/credits", async (
      AccountSecurityService accountSecurity,
      HttpContext context
    ) =>
    {
      var user = accountSecurity.Authenticate(context);
      if (user is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var credits = await accountSecurity.CreditsAsync(user, context.RequestAborted);
      return credits is null
        ? Error(StatusCodes.Status401Unauthorized, "Authentication is required.")
        : Json(credits, GifForgeJsonSerializerContext.Default.CreditBalanceResponse);
    });

    app.MapGet("/v1/iap/products", async (
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var user = accountSecurity.Authenticate(context);
      if (user is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckPurchase(context, user));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      return Json(
        await accountSecurity.ProductsAsync(context.RequestAborted),
        GifForgeJsonSerializerContext.Default.IapProductsResponse
      );
    });

    app.MapPost("/v1/iap/transactions", async (
      IapTransactionSubmissionRequest request,
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var user = accountSecurity.Authenticate(context);
      if (user is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckPurchase(context, user));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      var result = await accountSecurity.ProcessTransactionAsync(user, request, context.RequestAborted);
      return result is null
        ? Error(StatusCodes.Status401Unauthorized, "Transaction could not be verified.")
        : Json(result, GifForgeJsonSerializerContext.Default.IapTransactionSubmissionResponse);
    });

    app.MapPost("/v1/apple/app-store-server-notifications", async (
      AppStoreServerNotificationRequest request,
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAuth(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      await accountSecurity.ProcessAppStoreNotificationAsync(request, context.RequestAborted);
      return Json(
        new AppStoreServerNotificationResponse("accepted"),
        GifForgeJsonSerializerContext.Default.AppStoreServerNotificationResponse
      );
    });

    app.MapPost("/v1/apple/sign-in-server-notifications", async (
      SignInWithAppleNotificationRequest request,
      AccountSecurityService accountSecurity,
      GifForgeRateLimiter rateLimiter,
      HttpContext context
    ) =>
    {
      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckAuth(context));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      var accepted = await accountSecurity.ProcessSignInWithAppleNotificationAsync(request, context.RequestAborted);
      return accepted
        ? Json(
          new SignInWithAppleNotificationResponse("accepted"),
          GifForgeJsonSerializerContext.Default.SignInWithAppleNotificationResponse
        )
        : Error(StatusCodes.Status401Unauthorized, "Sign in with Apple notification could not be verified.");
    });

    app.MapPost("/v1/generations", async (
      GenerationRequest request,
      HttpContext context,
      IGenerationProvider provider,
      IJobStore jobStore,
      IGenerationJobDispatcher jobDispatcher,
      IAppAttestService appAttest,
      BackendOptions options,
      GenerationRetryOptions retryOptions,
      IGenerationEventSink generationEvents,
      GifForgeRateLimiter rateLimiter,
      AccountSecurityService accountSecurity,
      KeyedAsyncLock generationJobLocks
    ) =>
    {
      var authenticatedUser = accountSecurity.Authenticate(context);
      if (accountSecurity.AuthRequired && authenticatedUser is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckGeneration(context, authenticatedUser));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      if (!await appAttest.IsAuthorizedAsync(context, context.RequestAborted))
      {
        return Error(StatusCodes.Status401Unauthorized, "App Attest authorization is required.");
      }

      var validation = ModerationPolicy.Validate(request);
      if (!validation.IsValid)
      {
        return Error(validation.StatusCode, validation.Message);
      }

      // Deterministic job ids make resubmission of the same client request (for
      // example a retry after a lost 202) idempotent instead of double-charging.
      var jobId = string.IsNullOrWhiteSpace(request.Id)
        ? Guid.NewGuid().ToString("D")
        : DeterministicJobId(authenticatedUser?.UserId.ToString("D"), request);

      // Two requests carrying the same client-supplied idempotency key can arrive
      // genuinely concurrently (client retry racing the original, or a duplicated
      // send). Without this, both pass the "does a job already exist" check below
      // before either has created one, so the provider gets charged twice. Serialize
      // per jobId rather than globally so unrelated submissions never wait on this.
      await using var jobLockHandle = await generationJobLocks.AcquireAsync(jobId, context.RequestAborted);

      if (authenticatedUser is not null)
      {
        if (!string.IsNullOrWhiteSpace(request.RetryOfJobId) &&
            !await accountSecurity.UserOwnsGenerationAsync(
              authenticatedUser,
              request.RetryOfJobId,
              context.RequestAborted
            ))
        {
          return Error(StatusCodes.Status403Forbidden, "Generation access is not allowed.");
        }
      }

      var retryContext = await RetryContextForAsync(request, jobStore, retryOptions, context.RequestAborted);
      if (!retryContext.IsValid)
      {
        return Error(StatusCodes.Status409Conflict, retryContext.ErrorMessage ?? "Retry is not available.");
      }

      if (!string.IsNullOrWhiteSpace(request.Id))
      {
        var existingJob = await jobStore.GetAsync(jobId, context.RequestAborted);
        if (existingJob is not null && !existingJob.IsExpired(DateTimeOffset.UtcNow))
        {
          int replayedCredits;
          try
          {
            replayedCredits = EstimateGenerationCredits(provider, request, retryContext).RequiredCredits;
          }
          catch (GenerationPermanentFailureException)
          {
            replayedCredits = 1;
          }

          var existingStatusUrl = $"{RequestBaseUrl(context, options)}/v1/generations/{existingJob.Id}";
          return Json(
            new JobSubmissionResponse(existingJob.Id, "queued", existingStatusUrl, existingJob.ExpiresAt, replayedCredits),
            GifForgeJsonSerializerContext.Default.JobSubmissionResponse,
            statusCode: StatusCodes.Status202Accepted
          );
        }
      }

      if (provider is IModelCostRefreshAwareGenerationProvider costAwareProvider)
      {
        try
        {
          await costAwareProvider.EnsureModelCostsFreshAsync(
            request,
            retryContext.AttemptedProviders,
            retryContext.AttemptedModelIds,
            context.RequestAborted
          );
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
          return Error(StatusCodes.Status422UnprocessableEntity, "Model costs are unavailable; the generation was not submitted.");
        }
      }

      GenerationCreditEstimate creditEstimate;
      try
      {
        creditEstimate = EstimateGenerationCredits(provider, request, retryContext);
      }
      catch (GenerationPermanentFailureException)
      {
        return Error(StatusCodes.Status422UnprocessableEntity, "Generation provider rejected the request.");
      }

      CreditReservation? reservation = null;
      if (authenticatedUser is not null)
      {
        reservation = await accountSecurity.ReserveGenerationCreditAsync(
          authenticatedUser,
          jobId,
          creditEstimate.RequiredCredits,
          context.RequestAborted
        );
        if (reservation is null)
        {
          return Error(StatusCodes.Status402PaymentRequired, "Insufficient credits.");
        }
      }

      ProviderJob providerJob;
      try
      {
        providerJob = retryContext.IsRetry && provider is IRetryAwareGenerationProvider retryProvider
          ? await retryProvider.SubmitRetryGenerationAsync(
            request,
            retryContext.AttemptedProviders,
            retryContext.AttemptedModelIds,
            context.RequestAborted
          )
          : retryContext.IsRetry
            ? throw new GenerationPermanentFailureException("Configured provider does not support retry routing.")
            : await provider.SubmitGenerationAsync(request, context.RequestAborted);
      }
      catch (GenerationPermanentFailureException)
      {
        if (reservation is not null)
        {
          await accountSecurity.ReleaseGenerationCreditAsync(jobId, "provider_rejected", context.RequestAborted);
        }
        return Error(StatusCodes.Status422UnprocessableEntity, "Generation provider rejected the request.");
      }
      catch (HttpRequestException)
      {
        if (reservation is not null)
        {
          await accountSecurity.ReleaseGenerationCreditAsync(jobId, "provider_unavailable", context.RequestAborted);
        }
        return Error(StatusCodes.Status503ServiceUnavailable, "Generation provider is temporarily unavailable.");
      }

      var jobRequest = GenerationRequestPrivacy.SanitizeForJobState(request);
      var job = await jobStore.CreateAsync(jobRequest, providerJob, context.RequestAborted, jobId);
      if (retryContext.IsRetry)
      {
        job = job with
        {
          AttemptCount = retryContext.AttemptCount + 1,
          AttemptedProviders = JoinAttempts(retryContext.AttemptedProviders.Append(providerJob.Provider)),
          AttemptedModelIds = JoinAttempts(
            string.IsNullOrWhiteSpace(providerJob.ModelId)
              ? retryContext.AttemptedModelIds
              : retryContext.AttemptedModelIds.Append(providerJob.ModelId)
          )
        };
        await jobStore.SaveAsync(job, context.RequestAborted);
      }
      await jobDispatcher.DispatchAsync(job, context.RequestAborted);
      generationEvents.Record(GenerationOperationalEvent.FromJob("generation.queued", job));
      var statusUrl = $"{RequestBaseUrl(context, options)}/v1/generations/{job.Id}";

      return Json(
        new JobSubmissionResponse(job.Id, "queued", statusUrl, job.ExpiresAt, creditEstimate.RequiredCredits),
        GifForgeJsonSerializerContext.Default.JobSubmissionResponse,
        statusCode: StatusCodes.Status202Accepted
      );
    });

    app.MapGet("/v1/generations/{jobId}", async (
      string jobId,
      HttpContext context,
      IJobStore jobStore,
      IAppAttestService appAttest,
      BackendOptions options,
      GenerationRetryOptions retryOptions,
      GifForgeRateLimiter rateLimiter,
      AccountSecurityService accountSecurity
    ) =>
    {
      var authenticatedUser = accountSecurity.Authenticate(context);
      if (accountSecurity.AuthRequired && authenticatedUser is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckGenerationStatus(context, authenticatedUser));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      if (!await appAttest.IsAuthorizedAsync(context, context.RequestAborted))
      {
        return Error(StatusCodes.Status401Unauthorized, "App Attest authorization is required.");
      }

      var job = await jobStore.GetAsync(jobId, context.RequestAborted);
      if (job is null)
      {
        return Error(StatusCodes.Status404NotFound, "Generation job was not found.");
      }

      if (authenticatedUser is not null &&
          !await accountSecurity.UserOwnsGenerationAsync(authenticatedUser, job.Id, context.RequestAborted))
      {
        return Error(StatusCodes.Status403Forbidden, "Generation access is not allowed.");
      }

      if (job.IsExpired(DateTimeOffset.UtcNow))
      {
        return Error(StatusCodes.Status410Gone, "Generation job has expired.");
      }

      var status = jobStore.StatusFor(job);
      var downloadUrl = status == GenerationJobStatus.Succeeded
        ? $"{RequestBaseUrl(context, options)}/v1/generations/{job.Id}/result"
        : null;
      var retryAvailable = status == GenerationJobStatus.Failed && job.AttemptCount < retryOptions.MaxAttempts;

      return Json(
        new JobStatusResponse(
          job.Id,
          status.JsonValue(),
          downloadUrl,
          status == GenerationJobStatus.Failed ? job.FailedMessage : null,
          job.ExpiresAt,
          retryAvailable,
          retryAvailable ? "provider_failed" : null,
          retryAvailable ? job.Id : null
        ),
        GifForgeJsonSerializerContext.Default.JobStatusResponse
      );
    });

    app.MapGet("/v1/generations/{jobId}/result", async (
      string jobId,
      IGenerationProvider provider,
      IJobStore jobStore,
      IGenerationResultStore resultStore,
      IAppAttestService appAttest,
      HttpContext context,
      CancellationToken cancellationToken,
      GifForgeRateLimiter rateLimiter,
      AccountSecurityService accountSecurity
    ) =>
    {
      var authenticatedUser = accountSecurity.Authenticate(context);
      if (accountSecurity.AuthRequired && authenticatedUser is null)
      {
        return Error(StatusCodes.Status401Unauthorized, "Authentication is required.");
      }

      var rateLimit = EnforceRateLimit(context, rateLimiter.CheckGenerationStatus(context, authenticatedUser));
      if (rateLimit is not null)
      {
        return rateLimit;
      }

      if (!await appAttest.IsAuthorizedAsync(context, cancellationToken))
      {
        return Error(StatusCodes.Status401Unauthorized, "App Attest authorization is required.");
      }

      var job = await jobStore.GetAsync(jobId, cancellationToken);
      if (job is null)
      {
        return Error(StatusCodes.Status404NotFound, "Generation job was not found.");
      }

      if (authenticatedUser is not null &&
          !await accountSecurity.UserOwnsGenerationAsync(authenticatedUser, job.Id, cancellationToken))
      {
        return Error(StatusCodes.Status403Forbidden, "Generation access is not allowed.");
      }

      if (job.IsExpired(DateTimeOffset.UtcNow))
      {
        return Error(StatusCodes.Status410Gone, "Generation result has expired.");
      }

      if (jobStore.StatusFor(job) != GenerationJobStatus.Succeeded)
      {
        return Error(StatusCodes.Status409Conflict, "Generation result is not ready.");
      }

      var result = string.IsNullOrWhiteSpace(job.ResultBlobName)
        ? await provider.GetResultAsync(job, cancellationToken)
        : await resultStore.ReadAsync(job, cancellationToken);

      return Results.Bytes(result.Bytes, result.ContentType);
    });

    app.MapPost("/v1/provider-callbacks/{jobId}", async (
      string jobId,
      ProviderCallbackRequest callback,
      HttpContext context,
      IJobStore jobStore,
      IGenerationResultStore resultStore,
      IGenerationEventSink generationEvents,
      IConfiguration configuration,
      CancellationToken cancellationToken,
      AccountSecurityService accountSecurity
    ) =>
    {
      var expectedSecret = configuration["GIFFORGE_PROVIDER_CALLBACK_SECRET"];
      if (string.IsNullOrWhiteSpace(expectedSecret))
      {
        return Error(StatusCodes.Status503ServiceUnavailable, "Provider callbacks are not configured.");
      }

      var presentedSecret = context.Request.Headers["X-GifForge-Provider-Callback-Secret"].ToString();
      if (!CryptographicOperations.FixedTimeEquals(
        Encoding.UTF8.GetBytes(presentedSecret),
        Encoding.UTF8.GetBytes(expectedSecret)
      ))
      {
        return Error(StatusCodes.Status401Unauthorized, "Provider callback authorization is required.");
      }

      var job = await jobStore.GetAsync(jobId, cancellationToken);
      if (job is null)
      {
        return Error(StatusCodes.Status404NotFound, "Generation job was not found.");
      }

      if (!string.IsNullOrWhiteSpace(callback.ProviderJobId) &&
          !string.Equals(callback.ProviderJobId, job.ProviderJobId, StringComparison.Ordinal))
      {
        return Error(StatusCodes.Status409Conflict, "Provider job id does not match the generation job.");
      }

      var status = callback.Status.Trim().ToLowerInvariant();
      if (status is "failed" or "error")
      {
        var failed = job with
        {
          Status = GenerationJobStatus.Failed,
          FailedMessage = "Generation provider reported failure.",
          UpdatedAt = DateTimeOffset.UtcNow
        };
        await jobStore.SaveAsync(failed, cancellationToken);
        await accountSecurity.ReleaseGenerationCreditAsync(job.Id, "provider_callback_failure", cancellationToken);
        generationEvents.Record(GenerationOperationalEvent.FromJob(
          "generation.failed",
          failed,
          failureKind: "provider_callback_failure"
        ));
        return Results.Accepted();
      }

      if (status is not ("succeeded" or "completed" or "complete"))
      {
        return Results.Accepted();
      }

      if (string.IsNullOrWhiteSpace(callback.AssetUrl))
      {
        return Error(StatusCodes.Status400BadRequest, "Successful callbacks must include assetUrl.");
      }

      // The asset URL is caller-supplied: restrict fetches to explicitly allowlisted
      // provider hosts over HTTPS so the callback cannot be used for SSRF from the
      // managed-identity workload, and bound the download size and duration.
      if (!IsAllowedCallbackAssetUrl(callback.AssetUrl, configuration, out var assetUri))
      {
        return Error(StatusCodes.Status400BadRequest, "Callback assetUrl host is not allowed.");
      }

      byte[] bytes;
      try
      {
        using var assetResponse = await CallbackAssetHttpClient.GetAsync(
          assetUri,
          HttpCompletionOption.ResponseHeadersRead,
          cancellationToken
        );
        assetResponse.EnsureSuccessStatusCode();
        if (assetResponse.Content.Headers.ContentLength is > MaxCallbackAssetBytes)
        {
          return Error(StatusCodes.Status400BadRequest, "Callback asset is too large.");
        }

        await using var assetStream = await assetResponse.Content.ReadAsStreamAsync(cancellationToken);
        using var buffer = new MemoryStream();
        await CopyBoundedAsync(assetStream, buffer, MaxCallbackAssetBytes, cancellationToken);
        bytes = buffer.ToArray();
      }
      catch (HttpRequestException)
      {
        return Error(StatusCodes.Status502BadGateway, "Callback asset could not be downloaded.");
      }
      catch (InvalidOperationException)
      {
        return Error(StatusCodes.Status400BadRequest, "Callback asset is too large.");
      }

      if (bytes.Length == 0)
      {
        return Error(StatusCodes.Status400BadRequest, "Callback asset is empty.");
      }

      var stored = await resultStore
        .SaveAsync(job.Id, new GeneratedMotionResult(GenerationResultContentTypes.Mp4, bytes), cancellationToken)
        .ConfigureAwait(false);
      var succeeded = job with
      {
        Status = GenerationJobStatus.Succeeded,
        ResultBlobName = stored.BlobName,
        ResultContentType = stored.ContentType,
        UpdatedAt = DateTimeOffset.UtcNow
      };
      await jobStore.SaveAsync(succeeded, cancellationToken);
      await accountSecurity.CaptureGenerationCreditAsync(job.Id, cancellationToken);
      generationEvents.Record(GenerationOperationalEvent.FromJob(
        "generation.succeeded",
        succeeded,
        resultContentType: stored.ContentType
      ));
      return Results.Accepted();
    });
  }

  private static async Task<RetryContext> RetryContextForAsync(
    GenerationRequest request,
    IJobStore jobStore,
    GenerationRetryOptions retryOptions,
    CancellationToken cancellationToken
  )
  {
    if (string.IsNullOrWhiteSpace(request.RetryOfJobId))
    {
      return RetryContext.NotRetry;
    }

    var previous = await jobStore.GetAsync(request.RetryOfJobId, cancellationToken).ConfigureAwait(false);
    if (previous is null)
    {
      return RetryContext.Invalid("Original generation job was not found.");
    }

    if (previous.IsExpired(DateTimeOffset.UtcNow))
    {
      return RetryContext.Invalid("Original generation job has expired.");
    }

    if (previous.Status != GenerationJobStatus.Failed)
    {
      return RetryContext.Invalid("Only failed generation jobs can be retried.");
    }

    if (previous.AttemptCount >= retryOptions.MaxAttempts)
    {
      return RetryContext.Invalid("Generation retry limit has been reached.");
    }

    var attemptedProviders = SplitAttempts(previous.AttemptedProviders);
    attemptedProviders.Add(previous.Provider);
    var attemptedModelIds = SplitAttempts(previous.AttemptedModelIds);
    if (!string.IsNullOrWhiteSpace(previous.ProviderModelId))
    {
      attemptedModelIds.Add(previous.ProviderModelId);
    }

    return RetryContext.Valid(previous.AttemptCount, attemptedProviders, attemptedModelIds);
  }

  private static HashSet<string> SplitAttempts(string attempts) =>
    attempts
      .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
      .ToHashSet(StringComparer.OrdinalIgnoreCase);

  private static string JoinAttempts(IEnumerable<string> attempts) =>
    string.Join(',', attempts.Where(item => !string.IsNullOrWhiteSpace(item)).Distinct(StringComparer.OrdinalIgnoreCase));

  private static GenerationCreditEstimate EstimateGenerationCredits(
    IGenerationProvider provider,
    GenerationRequest request,
    RetryContext retryContext
  ) =>
    provider is IGenerationCreditEstimator estimator
      ? estimator.EstimateGenerationCredits(
        request,
        retryContext.AttemptedProviders,
        retryContext.AttemptedModelIds
      )
      : new GenerationCreditEstimate(1, provider.Name, null, null);

  private static IResult Json<T>(T value, JsonTypeInfo<T> jsonTypeInfo, int? statusCode = null, string? contentType = null) =>
    Results.Json(value, jsonTypeInfo, contentType: contentType, statusCode: statusCode);

  private static IResult Error(int statusCode, string message) =>
    Json(
      new ErrorResponse(statusCode >= 500 ? "internal_error" : "invalid_request", message),
      GifForgeJsonSerializerContext.Default.ErrorResponse,
      statusCode: statusCode
    );

  private static IResult? EnforceRateLimit(HttpContext context, RateLimitDecision decision)
  {
    if (decision.Allowed)
    {
      return null;
    }

    var retryAfterSeconds = Math.Max(1, (int)Math.Ceiling(decision.RetryAfter.TotalSeconds));
    context.Response.Headers.RetryAfter = retryAfterSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture);
    return Error(StatusCodes.Status429TooManyRequests, "Too many requests. Try again later.");
  }

  /// <summary>
  /// Derives a stable job id from the caller identity and the client-supplied
  /// request id (plus the retry lineage, so a retry is a distinct job while its
  /// own resubmission is not). Same inputs always map to the same job.
  /// </summary>
  private static string DeterministicJobId(string? userId, GenerationRequest request)
  {
    var name = $"gifforge-generation:{userId ?? "anonymous"}:{request.Id}:{request.RetryOfJobId ?? string.Empty}";
    var hash = SHA256.HashData(Encoding.UTF8.GetBytes(name));
    var bytes = hash.AsSpan(0, 16).ToArray();
    bytes[6] = (byte)((bytes[6] & 0x0F) | 0x50);
    bytes[8] = (byte)((bytes[8] & 0x3F) | 0x80);
    return new Guid(bytes).ToString("D");
  }

  private const long MaxCallbackAssetBytes = 100_000_000;

  private static readonly HttpClient CallbackAssetHttpClient = new(new SocketsHttpHandler
  {
    PooledConnectionLifetime = TimeSpan.FromMinutes(5),
    AllowAutoRedirect = false
  })
  {
    Timeout = TimeSpan.FromSeconds(60)
  };

  private static bool IsAllowedCallbackAssetUrl(
    string assetUrl,
    IConfiguration configuration,
    out Uri assetUri
  )
  {
    assetUri = null!;
    if (!Uri.TryCreate(assetUrl, UriKind.Absolute, out var parsed) ||
        parsed.Scheme != Uri.UriSchemeHttps)
    {
      return false;
    }

    var allowedHosts = (configuration["GIFFORGE_PROVIDER_CALLBACK_ASSET_HOSTS"] ?? string.Empty)
      .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    if (allowedHosts.Length == 0)
    {
      return false;
    }

    foreach (var allowedHost in allowedHosts)
    {
      if (parsed.Host.Equals(allowedHost, StringComparison.OrdinalIgnoreCase) ||
          parsed.Host.EndsWith($".{allowedHost}", StringComparison.OrdinalIgnoreCase))
      {
        assetUri = parsed;
        return true;
      }
    }

    return false;
  }

  private static async Task CopyBoundedAsync(
    Stream source,
    Stream destination,
    long maxBytes,
    CancellationToken cancellationToken
  )
  {
    var buffer = new byte[81920];
    long total = 0;
    int read;
    while ((read = await source.ReadAsync(buffer, cancellationToken)) > 0)
    {
      total += read;
      if (total > maxBytes)
      {
        throw new InvalidOperationException("Callback asset exceeds the maximum allowed size.");
      }

      await destination.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
    }
  }

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

internal sealed record RetryContext(
  bool IsRetry,
  bool IsValid,
  int AttemptCount,
  HashSet<string> AttemptedProviders,
  HashSet<string> AttemptedModelIds,
  string? ErrorMessage
)
{
  public static RetryContext NotRetry { get; } =
    new(false, true, 0, new(StringComparer.OrdinalIgnoreCase), new(StringComparer.OrdinalIgnoreCase), null);

  public static RetryContext Valid(
    int attemptCount,
    HashSet<string> attemptedProviders,
    HashSet<string> attemptedModelIds
  ) =>
    new(true, true, attemptCount, attemptedProviders, attemptedModelIds, null);

  public static RetryContext Invalid(string message) =>
    new(true, false, 0, new(StringComparer.OrdinalIgnoreCase), new(StringComparer.OrdinalIgnoreCase), message);
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(HealthResponse))]
[JsonSerializable(typeof(ErrorResponse))]
[JsonSerializable(typeof(GenerationRequest))]
[JsonSerializable(typeof(SourceMediaRequest))]
[JsonSerializable(typeof(JobSubmissionResponse))]
[JsonSerializable(typeof(JobStatusResponse))]
[JsonSerializable(typeof(ProviderCallbackRequest))]
[JsonSerializable(typeof(FrameSequenceAsset))]
[JsonSerializable(typeof(FrameSpec))]
[JsonSerializable(typeof(GenerationQueueMessage))]
[JsonSerializable(typeof(AppAttestChallengeResponse))]
[JsonSerializable(typeof(AppAttestAttestationRequest))]
[JsonSerializable(typeof(AppAttestSessionResponse))]
[JsonSerializable(typeof(AppleAuthRequest))]
[JsonSerializable(typeof(RefreshTokenRequest))]
[JsonSerializable(typeof(LogoutRequest))]
[JsonSerializable(typeof(AuthTokenResponse))]
[JsonSerializable(typeof(MeResponse))]
[JsonSerializable(typeof(CreditBalanceResponse))]
[JsonSerializable(typeof(IapProductResponse))]
[JsonSerializable(typeof(IapProductsResponse))]
[JsonSerializable(typeof(IapTransactionSubmissionRequest))]
[JsonSerializable(typeof(IapTransactionSubmissionResponse))]
[JsonSerializable(typeof(AppStoreServerNotificationRequest))]
[JsonSerializable(typeof(AppStoreServerNotificationResponse))]
[JsonSerializable(typeof(SignInWithAppleNotificationRequest))]
[JsonSerializable(typeof(SignInWithAppleNotificationResponse))]
[JsonSerializable(typeof(ModelCostRefreshRequest))]
[JsonSerializable(typeof(ModelCostRefreshResponse))]
[JsonSerializable(typeof(ModelCostRefreshProviderResponse))]
internal partial class GifForgeJsonSerializerContext : JsonSerializerContext;

public sealed record HealthResponse(bool Ok, string Provider, string Mode);
public sealed record ErrorResponse(string Error, string Message);
public sealed record ModelCostRefreshRequest(string? Provider);
public sealed record ModelCostRefreshResponse(IReadOnlyList<ModelCostRefreshProviderResponse> Providers);
public sealed record ModelCostRefreshProviderResponse(
  string Provider,
  bool Succeeded,
  bool UsedStaleCache,
  int ValuesWritten,
  DateTimeOffset? LastSuccessfulRefreshAtUtc,
  string? Error
);

public sealed record JobSubmissionResponse(
  string JobId,
  string Status,
  string StatusUrl,
  DateTimeOffset ExpiresAt,
  int RequiredCredits
);
public sealed record JobStatusResponse(
  string JobId,
  string Status,
  string? DownloadUrl,
  string? Message,
  DateTimeOffset ExpiresAt,
  bool RetryAvailable = false,
  string? RetryReason = null,
  string? RetryOfJobId = null
);

public sealed record ProviderCallbackRequest(
  string Status,
  string? ProviderJobId,
  string? AssetUrl,
  string? ContentType
);
