import SwiftUI

/// A small reusable status card describing whether on-device Apple Intelligence
/// planning is available on this device.
///
/// This view is intentionally "dumb": it only renders the state it is given.
/// Wiring it up to real `FoundationModels` availability (and richer unavailable
/// reasons) is expected to land separately; call sites should compute
/// `isAvailable`/`reason` and pass them in.
struct AppleIntelligenceStatusCard: View {
  var isAvailable: Bool
  var reason: String?

  var body: some View {
    AppCard {
      VStack(alignment: .leading, spacing: 8) {
        Label(String(localized: "Apple Intelligence"), systemImage: "brain.head.profile")
          .font(.headline)
        Text(isAvailable ? String(localized: "On-device planning available") : String(localized: "On-device planning unavailable"))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(isAvailable ? .primary : .secondary)
        Text(reason ?? defaultExplanation)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var defaultExplanation: String {
    isAvailable
      ? String(localized: "GifForge can use on-device planning to help prepare prompts before generation.")
      : String(localized: "On-device planning is not available on this device right now. GifForge still works without it.")
  }
}
