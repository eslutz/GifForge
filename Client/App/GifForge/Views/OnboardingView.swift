import GifForgeCore
import SwiftUI

/// First-launch onboarding flow. Presented as a full-screen cover from
/// `AppShellView` until the user finishes it. Entirely offline — no network
/// calls are made anywhere in this flow.
struct OnboardingView: View {
  var onFinish: () -> Void

  @State private var currentPage = 0
  @State private var plannerAvailability: PlannerAvailability = PromptPlannerFactory.currentAvailability()

  private let lastPageIndex = 2

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $currentPage) {
        OnboardingIntroPage()
          .tag(0)
        OnboardingMessagesUsagePage()
          .tag(1)
        OnboardingIntelligencePage(
          isAvailable: plannerAvailability.isOnDevice,
          reason: {
            if case let .unavailable(reason) = plannerAvailability {
              return reason.displayMessage
            }
            return nil
          }()
        )
        .tag(2)
      }
      .tabViewStyle(.page)
      .indexViewStyle(.page(backgroundDisplayMode: .always))

      Button {
        if currentPage < lastPageIndex {
          withAnimation {
            currentPage += 1
          }
        } else {
          onFinish()
        }
      } label: {
        Text(currentPage < lastPageIndex ? String(localized: "Next") : String(localized: "Get Started"))
          .font(.headline)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .padding(.horizontal, 24)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
  }
}

/// SwiftUI's `.page` index dots (`.indexViewStyle(.page(backgroundDisplayMode:
/// .always))`) are not given separate layout space — they overlay directly
/// inside the TabView's own bounds near the bottom edge, and the dots
/// themselves never grow with Dynamic Type. At accessibility Dynamic Type
/// sizes, a page's last line of body text can grow tall enough to land
/// underneath them. `safeAreaInset` (not trailing content padding — padding
/// added after the last line only extends the scrollable area *past* the
/// fold, it doesn't move the fold itself) shrinks the ScrollView's own
/// viewport, so content actually clears the dots at the initial,
/// unscrolled position. 90pt (roughly one AXXXL body-text line) verified
/// visually against the dots' rendered height, not just a guess. Only
/// applied at accessibility sizes so normal-size onboarding keeps its
/// existing spacing.
private struct ReservesSpaceForPageIndicator: ViewModifier {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    content.safeAreaInset(edge: .bottom) {
      if dynamicTypeSize.isAccessibilitySize {
        // Fully transparent content (Color.clear, Spacer) is not reserved by
        // safeAreaInset — SwiftUI appears to skip inset space for content
        // with zero effective opacity, confirmed empirically. An opaque
        // color matching the page background reserves the space and is
        // visually seamless.
        Color(.systemBackground).frame(height: 90)
      }
    }
  }
}

private extension View {
  func reservingSpaceForPageIndicator() -> some View {
    modifier(ReservesSpaceForPageIndicator())
  }
}

private struct OnboardingIntroPage: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Image(systemName: "sparkles")
          .font(.system(size: 40, weight: .semibold))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text(String(localized: "Welcome to GifForge"))
          .font(.largeTitle.bold())
        Text(String(localized: "GifForge turns a prompt or a selected photo into a shareable animated GIF, ready to review and place into your conversation."))
          .font(.body)
          // Lead description, not de-emphasized metadata — matches the
          // OverviewView fix for the same borderline-contrast audit finding.
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 32)
    }
    .reservingSpaceForPageIndicator()
  }
}

private struct OnboardingMessagesUsagePage: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Image(systemName: "message.fill")
          .font(.system(size: 40, weight: .semibold))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text(String(localized: "Use GifForge from Messages"))
          .font(.largeTitle.bold())
        Text(String(localized: "GifForge only works from inside the Messages app."))
          .font(.body)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 12) {
          Label(String(localized: "Open a conversation in Messages"), systemImage: "1.circle.fill")
          Label(String(localized: "Tap the app drawer — the row of app icons above the keyboard"), systemImage: "2.circle.fill")
          Label(String(localized: "Select GifForge from the drawer to start creating"), systemImage: "3.circle.fill")
        }
        .font(.body)
        .padding(.top, 4)

        Text(String(localized: "There isn't a way to jump straight into the Messages app drawer from here, so look for GifForge the next time you're chatting."))
          .font(.footnote)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 32)
    }
    .reservingSpaceForPageIndicator()
  }
}

private struct OnboardingIntelligencePage: View {
  var isAvailable: Bool
  var reason: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Image(systemName: "brain.head.profile")
          .font(.system(size: 40, weight: .semibold))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text(String(localized: "On-Device Planning"))
          .font(.largeTitle.bold())
        Text(String(localized: "When available, GifForge uses Apple Intelligence on this device to help plan prompts before generation."))
          .font(.body)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)

        AppleIntelligenceStatusCard(isAvailable: isAvailable, reason: reason)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 32)
    }
    .reservingSpaceForPageIndicator()
  }
}
