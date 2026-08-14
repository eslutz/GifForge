import SwiftUI

struct OverviewView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "sparkles")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
          Text(String(localized: "Make GIFs for Messages"))
            .font(.largeTitle.bold())
          Text(String(localized: "Turn a prompt or selected image into a shareable GIF, review it, then place it into your conversation when it is ready."))
            .font(.body)
            // This is the lead value-prop sentence, not de-emphasized
            // metadata — .secondary at body size measured borderline on an
            // automated contrast audit (XCUIApplication.performAccessibilityAudit).
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(spacing: 12) {
          FeatureCard(
            title: String(localized: "Prompt to motion"),
            subtitle: String(localized: "Describe the moment you want and GifForge prepares an animated result."),
            // Not "text.quote": that glyph's quote-mark shapes were flagged by
            // XCUIApplication.performAccessibilityAudit as "Potentially
            // inaccessible text" — its on-device text detector reads the
            // rendered pixels independent of the accessibility tree, and this
            // icon is correctly .accessibilityHidden (decorative), so nothing
            // accessible "covers" what looks like text-shaped content.
            // Confirmed by bisection: swapping the symbol alone clears the
            // audit finding.
            systemImage: "wand.and.rays"
          )
          FeatureCard(
            title: String(localized: "Photo friendly"),
            subtitle: String(localized: "Animate one selected image without asking for broad photo library access."),
            systemImage: "photo.on.rectangle"
          )
          FeatureCard(
            title: String(localized: "Send intentionally"),
            subtitle: String(localized: "Messages keeps the final send action in your control."),
            systemImage: "paperplane"
          )
        }

        AppCard {
          VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Privacy"), systemImage: "hand.raised")
              .font(.headline)
            Text(String(localized: "Selected media and prompts are used for generation. Generated GIFs and resumable job data stay on this device until you clear them."))
              .font(.subheadline)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
  }
}
