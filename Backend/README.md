# Gifster Backend

Gifster uses an ASP.NET Core Minimal API backend configured for Native AOT and intended for Azure Container Apps.

The backend is provider-neutral. The app never calls external AI media providers directly; it submits structured generation requests to this service, which validates and moderates requests, owns provider credentials, tracks jobs, and returns temporary result URLs.

## Local Development

```bash
dotnet run --project Backend/Gifster.Backend.csproj
```

The backend listens on `http://127.0.0.1:8787` by default when launched directly.

## Tests

```bash
dotnet run --project Backend.Tests/Gifster.Backend.Tests.csproj
```

The test harness verifies the demo provider, job lifecycle, fake frame-sequence output, and moderation rejection without binding a local server.

## Azure Container Apps Direction

Production should run this API as a small containerized Minimal API on Azure Container Apps using a consumption workload profile.

Recommended supporting services:

- Azure Queue Storage for asynchronous provider orchestration.
- Azure Blob Storage for provider output and temporary downloadable media.
- Azure Table Storage or Cosmos DB for durable job state.
- Azure Key Vault or Container Apps secrets for provider credentials.
- Managed identity for Azure resource access.
- Application Insights for logs, metrics, and request tracing.

Native AOT is enabled in `Gifster.Backend.csproj` to reduce cold-start overhead and memory usage compared with a standard JIT ASP.NET Core deployment.
