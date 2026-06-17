namespace GifForge.CostUpdater.Tests;

public sealed class LumaPricingSourceTests
{
  [Fact]
  public void ParsesStrictLumaHtmlFixture()
  {
    const string html = """
    <section id="api-pricing">
      <div data-model-cost-key="ray-3.2:text-to-video" data-cost-usd="0.16">Ray 3.2 text</div>
      <div data-model-cost-key="ray-3.2:image-to-video" data-cost-usd="0.18">Ray 3.2 image</div>
      <div data-model-cost-key="ray-3.2:video-to-video" data-cost-usd="0.22">Ray 3.2 video</div>
    </section>
    """;

    var updates = LumaPricingSource.ParseHtml(
      html,
      [
        new("luma", "ray-3.2:text-to-video", "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_TEXT_TO_VIDEO", "text"),
        new("luma", "ray-3.2:image-to-video", "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_IMAGE_TO_VIDEO", "image"),
        new("luma", "ray-3.2:video-to-video", "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_VIDEO_TO_VIDEO", "video")
      ]
    );

    Assert.Equal([0.16m, 0.18m, 0.22m], updates.Select(update => update.CostUsd));
  }

  [Fact]
  public void MalformedLumaHtmlProducesNoWrites()
  {
    var error = Assert.Throws<InvalidOperationException>(() => LumaPricingSource.ParseHtml(
      "<html><body>Ray pricing changed</body></html>",
      [
        new("luma", "ray-3.2:text-to-video", "GIFFORGE_MODEL_COST_USD_LUMA_RAY32_TEXT_TO_VIDEO", "text")
      ]
    ));

    Assert.Contains("did not include an unambiguous cost", error.Message);
  }
}
