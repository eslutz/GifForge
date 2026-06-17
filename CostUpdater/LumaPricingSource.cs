using System.Globalization;
using System.Text.RegularExpressions;

namespace GifForge.CostUpdater;

public sealed partial class LumaPricingSource(IHttpClientFactory httpClientFactory) : ProviderPricingSource
{
  public const string HttpClientName = "luma-pricing";

  public string ProviderName => "luma";

  public async Task<IReadOnlyList<ModelCostUpdate>> GetModelCostsUsdAsync(
    IReadOnlyList<ProviderModelMapping> mappings,
    CancellationToken cancellationToken
  )
  {
    var client = httpClientFactory.CreateClient(HttpClientName);
    var apiPage = await client.GetStringAsync("api", cancellationToken);
    var pricingPage = await client.GetStringAsync("pricing", cancellationToken);
    return ParseHtml($"{apiPage}\n{pricingPage}", mappings);
  }

  public static IReadOnlyList<ModelCostUpdate> ParseHtml(
    string html,
    IReadOnlyList<ProviderModelMapping> mappings
  ) =>
    mappings.Select(mapping => new ModelCostUpdate(
        mapping.AppConfigurationKey,
        FindCost(html, mapping.SourcePriceKey)
          ?? throw new InvalidOperationException($"Luma pricing page did not include an unambiguous cost for {mapping.SourcePriceKey}.")
      ))
      .ToArray();

  private static decimal? FindCost(string html, string sourcePriceKey)
  {
    var attributeMatch = AttributeCostRegex(sourcePriceKey).Match(html);
    if (attributeMatch.Success && TryParseCost(attributeMatch.Groups["cost"].Value, out var attributeCost))
    {
      return attributeCost;
    }

    var assignmentMatch = AssignmentCostRegex(sourcePriceKey).Match(html);
    if (assignmentMatch.Success && TryParseCost(assignmentMatch.Groups["cost"].Value, out var assignmentCost))
    {
      return assignmentCost;
    }

    return null;
  }

  private static Regex AttributeCostRegex(string sourcePriceKey) =>
    new(
      $"""data-model-cost-key=["']{Regex.Escape(sourcePriceKey)}["'][^>]*data-cost-usd=["'](?<cost>[0-9]+(?:\.[0-9]+)?)["']""",
      RegexOptions.IgnoreCase | RegexOptions.CultureInvariant
    );

  private static Regex AssignmentCostRegex(string sourcePriceKey) =>
    new(
      $"""{Regex.Escape(sourcePriceKey)}\s*[:=]\s*\$?(?<cost>[0-9]+(?:\.[0-9]+)?)""",
      RegexOptions.IgnoreCase | RegexOptions.CultureInvariant
    );

  private static bool TryParseCost(string value, out decimal cost) =>
    decimal.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out cost) && cost >= 0;
}
