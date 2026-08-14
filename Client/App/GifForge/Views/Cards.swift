import SwiftUI

/// `LabeledContent`'s built-in style renders its value in a secondary/gray
/// tone that measured as a hard contrast failure on an automated accessibility
/// audit (`XCUIApplication.performAccessibilityAudit`) in this app's Forms —
/// not a color this app chose, but Apple's own default component styling.
/// Rendering the value in the primary label color resolves it without losing
/// the label/value visual grouping `LabeledContent` provides.
struct PrimaryValueLabeledContentStyle: LabeledContentStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack {
      configuration.label
      Spacer()
      configuration.content
        .foregroundStyle(.primary)
    }
  }
}

struct AppCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(.quaternary, lineWidth: 1)
      }
  }
}

struct FeatureCard: View {
  var title: String
  var subtitle: String
  var systemImage: String

  var body: some View {
    AppCard {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: systemImage)
          .font(.title3.weight(.semibold))
          .foregroundStyle(.tint)
          .frame(width: 28)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.headline)
          Text(subtitle)
            .font(.subheadline)
            // .secondary at this size measured borderline on an automated
            // contrast audit (XCUIApplication.performAccessibilityAudit) —
            // this is the card's lead explanatory text, not decoration.
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}
