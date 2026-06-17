using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace GifForge.CostUpdater;

public sealed class FalPricingSource(IHttpClientFactory httpClientFactory, IConfiguration configuration)
  : ProviderPricingSource
{
  public const string HttpClientName = "fal-pricing";

  public string ProviderName => "fal.ai";

  public async Task<IReadOnlyList<ModelCostUpdate>> GetModelCostsUsdAsync(
    IReadOnlyList<ProviderModelMapping> mappings,
    CancellationToken cancellationToken
  )
  {
    using var request = new HttpRequestMessage(HttpMethod.Get, "v1/models/pricing");
    var apiKey = configuration["GIFFORGE_FAL_PRICING_API_KEY"] ?? configuration["GIFFORGE_FAL_API_KEY"];
    if (!string.IsNullOrWhiteSpace(apiKey))
    {
      request.Headers.Authorization = new AuthenticationHeaderValue("Key", apiKey);
    }

    var client = httpClientFactory.CreateClient(HttpClientName);
    using var response = await client.SendAsync(request, cancellationToken);
    response.EnsureSuccessStatusCode();

    await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
    using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
    return mappings.Select(mapping => new ModelCostUpdate(
        mapping.AppConfigurationKey,
        FindPrice(document.RootElement, mapping.SourcePriceKey)
          ?? throw new InvalidOperationException($"fal.ai pricing response did not include {mapping.SourcePriceKey}.")
      ))
      .ToArray();
  }

  private static decimal? FindPrice(JsonElement root, string sourcePriceKey)
  {
    foreach (var candidate in EnumerateObjects(root))
    {
      if (ObjectMatchesSource(candidate, sourcePriceKey) && TryReadPrice(candidate, out var price))
      {
        return price;
      }
    }

    return null;
  }

  private static IEnumerable<JsonElement> EnumerateObjects(JsonElement element)
  {
    if (element.ValueKind == JsonValueKind.Object)
    {
      yield return element;
      foreach (var property in element.EnumerateObject())
      {
        foreach (var child in EnumerateObjects(property.Value))
        {
          yield return child;
        }
      }
    }
    else if (element.ValueKind == JsonValueKind.Array)
    {
      foreach (var item in element.EnumerateArray())
      {
        foreach (var child in EnumerateObjects(item))
        {
          yield return child;
        }
      }
    }
  }

  private static bool ObjectMatchesSource(JsonElement candidate, string sourcePriceKey)
  {
    foreach (var property in candidate.EnumerateObject())
    {
      if (
        IsModelIdentifierProperty(property.Name)
        && property.Value.ValueKind == JsonValueKind.String
        && string.Equals(property.Value.GetString(), sourcePriceKey, StringComparison.OrdinalIgnoreCase)
      )
      {
        return true;
      }
    }

    return false;
  }

  private static bool IsModelIdentifierProperty(string name) =>
    name.Equals("id", StringComparison.OrdinalIgnoreCase)
    || name.Equals("model_id", StringComparison.OrdinalIgnoreCase)
    || name.Equals("modelId", StringComparison.OrdinalIgnoreCase)
    || name.Equals("endpoint_id", StringComparison.OrdinalIgnoreCase)
    || name.Equals("endpointId", StringComparison.OrdinalIgnoreCase);

  private static bool TryReadPrice(JsonElement candidate, out decimal price)
  {
    foreach (var property in candidate.EnumerateObject())
    {
      if (!IsPriceProperty(property.Name))
      {
        continue;
      }

      if (TryReadDecimal(property.Value, out price) && price >= 0)
      {
        return true;
      }
    }

    price = 0;
    return false;
  }

  private static bool IsPriceProperty(string name) =>
    name.Equals("price", StringComparison.OrdinalIgnoreCase)
    || name.Equals("price_usd", StringComparison.OrdinalIgnoreCase)
    || name.Equals("priceUsd", StringComparison.OrdinalIgnoreCase)
    || name.Equals("cost", StringComparison.OrdinalIgnoreCase)
    || name.Equals("cost_usd", StringComparison.OrdinalIgnoreCase)
    || name.Equals("costUsd", StringComparison.OrdinalIgnoreCase);

  private static bool TryReadDecimal(JsonElement element, out decimal value) =>
    element.ValueKind switch
    {
      JsonValueKind.Number => element.TryGetDecimal(out value),
      JsonValueKind.String => decimal.TryParse(
        element.GetString(),
        NumberStyles.Number,
        CultureInfo.InvariantCulture,
        out value
      ),
      _ => OutZero(out value)
    };

  private static bool OutZero(out decimal value)
  {
    value = 0;
    return false;
  }
}
