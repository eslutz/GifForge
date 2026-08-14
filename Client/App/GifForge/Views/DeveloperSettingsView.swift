import GifForgeCore
import SwiftUI

/// Label-above-value row for identifiers too long to sit beside their label
/// in a single line (UUIDs, tokens) — wraps naturally at any Dynamic Type size
/// instead of truncating.
private struct WrappingLabeledValue: View {
  var label: String
  var value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.primary)
      Text(value)
        .font(.body)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
    }
    .padding(.vertical, 2)
  }
}

struct DeveloperSettingsView: View {
  @Binding var backendBaseURL: String
  @Binding var backendRequiresAppAttest: Bool

  var userID: String?
  var appAccountToken: UUID?
  var accountKind: String?
  var recoveryProvider: String?
  var creditBalance: BackendCreditBalance?
  var settingsMessage: String?
  var isPreparingAppAttest: Bool
  var appAttestSessionIsReady: Bool
  var refreshAppAttestSession: () -> Void

  var body: some View {
    Form {
      Section(String(localized: "Build")) {
        LabeledContent(String(localized: "Version"), value: "\(Self.appVersion) (\(Self.buildNumber))")
        LabeledContent(String(localized: "Bundle"), value: Self.bundleIdentifier)
      }

      Section(String(localized: "Account State")) {
        // UUID-length values don't fit alongside their label in
        // LabeledContent's single-line HStack layout without truncating or
        // clipping at larger Dynamic Type sizes — stack label above value so
        // long identifiers can wrap across the full row width.
        WrappingLabeledValue(label: String(localized: "User"), value: userID ?? String(localized: "Not created"))
        LabeledContent(String(localized: "Kind"), value: accountKind ?? String(localized: "Unknown"))
        LabeledContent(String(localized: "Recovery"), value: recoveryProvider ?? String(localized: "None"))
        WrappingLabeledValue(
          label: String(localized: "App Account Token"),
          value: appAccountToken?.uuidString ?? String(localized: "Unavailable")
        )
        if let creditBalance {
          LabeledContent(String(localized: "Available Credits"), value: "\(creditBalance.availableCredits)")
          LabeledContent(String(localized: "Reserved Credits"), value: "\(creditBalance.reservedCredits)")
        }
      }

      Section(String(localized: "Backend")) {
        TextField(String(localized: "Base URL"), text: $backendBaseURL)
          .textInputAutocapitalization(.never)
          .textContentType(.URL)
          .keyboardType(.URL)
          .autocorrectionDisabled()
        Toggle(String(localized: "Require App Attest"), isOn: $backendRequiresAppAttest)
        LabeledContent(
          String(localized: "App Attest Session"),
          value: appAttestSessionIsReady ? String(localized: "Ready") : String(localized: "Not prepared")
        )
        if backendRequiresAppAttest {
          Button {
            refreshAppAttestSession()
          } label: {
            Label(String(localized: "Refresh App Attest Session"), systemImage: "checkmark.shield")
          }
          .disabled(isPreparingAppAttest)
        }
      }

      Section(String(localized: "Diagnostics")) {
        LabeledContent(String(localized: "Latest Message"), value: settingsMessage ?? String(localized: "None"))
        Text(String(localized: "Run the local backend with dotnet run from the Backend project. Use your Mac LAN IP for device testing."))
          .font(.caption)
          .foregroundStyle(.primary)
      }
    }
    .formStyle(.grouped)
    .labeledContentStyle(PrimaryValueLabeledContentStyle())
    .navigationTitle(String(localized: "Developer"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? String(localized: "Unknown")
  }

  private static var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? String(localized: "Unknown")
  }

  private static var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? String(localized: "Unknown")
  }
}
