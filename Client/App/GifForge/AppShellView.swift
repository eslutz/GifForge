import GifForgeCore
import AuthenticationServices
import CryptoKit
import OSLog
import Security
import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
private let gifforgeDefaults = UserDefaults(suiteName: AppStorageDirectories.appGroupIdentifier) ?? .standard

struct AppShellView: View {
  @State private var history: [GenerationHistoryItem] = []
  @State private var errorMessage: String?

  private let historyStore = GenerationHistoryStore(
    directoryURL: AppStorageDirectories.sharedContainerURL()
  )
  private let activeGenerationStore = ActiveGenerationStore(
    directoryURL: AppStorageDirectories.sharedContainerURL()
  )

  var body: some View {
    TabView {
      NavigationStack {
        OverviewView()
      }
      .tabItem {
        Label("GifForge", systemImage: "sparkles")
      }

      NavigationStack {
        HistoryView(history: history, clearHistory: clearHistory)
          .task {
            await loadHistory()
          }
      }
      .tabItem {
        Label("History", systemImage: "clock")
      }

      NavigationStack {
        SettingsView()
      }
      .tabItem {
        Label("Settings", systemImage: "gearshape")
      }
    }
    .alert("GifForge", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private func loadHistory() async {
    do {
      #if DEBUG
      try await seedHistoryForUITestsIfNeeded()
      #endif
      history = try await historyStore.load()
    } catch {
      errorMessage = error.gifforgeUserFacingMessage
    }
  }

  private func clearHistory() {
    Task {
      do {
        try await historyStore.clear()
        try await activeGenerationStore.clear()
        history = []
      } catch {
        errorMessage = error.gifforgeUserFacingMessage
      }
    }
  }

  #if DEBUG
  private func seedHistoryForUITestsIfNeeded() async throws {
    guard ProcessInfo.processInfo.environment["GIFFORGE_UI_TEST_SEED_HISTORY"] == "1" else {
      return
    }

    let existingHistory = try await historyStore.load()
    guard existingHistory.isEmpty else {
      return
    }

    let mediaDirectory = try AppStorageDirectories.generatedMediaDirectory()
    let gifURL = mediaDirectory.appending(path: "ui-test-history.gif")
    if !FileManager.default.fileExists(atPath: gifURL.path) {
      try Data("GIF89a".utf8).write(to: gifURL, options: .atomic)
    }

    try await historyStore.save(
      GenerationHistoryItem(
        prompt: "UI test prompt",
        captionText: "UI test caption",
        gifURL: gifURL
      )
    )
  }
  #endif
}

private struct OverviewView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "sparkles")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
          Text("Make GIFs for Messages")
            .font(.largeTitle.bold())
          Text("Turn a prompt or selected image into a shareable GIF, review it, then place it into your conversation when it is ready.")
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(spacing: 12) {
          FeatureCard(
            title: "Prompt to motion",
            subtitle: "Describe the moment you want and GifForge prepares an animated result.",
            systemImage: "text.quote"
          )
          FeatureCard(
            title: "Photo friendly",
            subtitle: "Animate one selected image without asking for broad photo library access.",
            systemImage: "photo.on.rectangle"
          )
          FeatureCard(
            title: "Send intentionally",
            subtitle: "Messages keeps the final send action in your control.",
            systemImage: "paperplane"
          )
        }

        AppCard {
          VStack(alignment: .leading, spacing: 8) {
            Label("Privacy", systemImage: "hand.raised")
              .font(.headline)
            Text("Selected media and prompts are used for generation. Generated GIFs and resumable job data stay on this device until you clear them.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
    .navigationTitle("GifForge")
  }
}

private struct HistoryView: View {
  var history: [GenerationHistoryItem]
  var clearHistory: () -> Void

  @State private var isConfirmingClearHistory = false

  var body: some View {
    List {
      if history.isEmpty {
        ContentUnavailableView(
          "No GIFs Yet",
          systemImage: "sparkles",
          description: Text("GIFs generated from Messages will appear here.")
        )
      } else {
        ForEach(history) { item in
          VStack(alignment: .leading, spacing: 10) {
            Text(item.prompt)
              .font(.headline)
              .lineLimit(2)
            if let caption = item.captionText, !caption.isEmpty {
              Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            ShareLink(item: item.gifURL) {
              Label("Share GIF", systemImage: "square.and.arrow.up")
            }
            .font(.subheadline.weight(.semibold))
          }
          .padding(.vertical, 6)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("History")
    .toolbar {
      Button(role: .destructive) {
        isConfirmingClearHistory = true
      } label: {
        Label("Clear", systemImage: "trash")
      }
      .disabled(history.isEmpty)
    }
    .alert("Clear History?", isPresented: $isConfirmingClearHistory) {
      Button("Cancel", role: .cancel) {}
      Button("Clear History", role: .destructive, action: clearHistory)
    } message: {
      Text("Delete generated GIF history and resumable job metadata from this device.")
    }
  }
}

private struct AppCard<Content: View>: View {
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

private struct FeatureCard: View {
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
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

private struct PrivacyDetailsView: View {
  var body: some View {
    Form {
      Section("Generation") {
        Text("Prompts and selected images are sent through the configured GifForge service to create media.")
        Text("Caption cleanup and prompt planning run locally when Apple Foundation Models are available.")
      }

      Section("On This Device") {
        Text("Generated GIFs and resumable job metadata are stored locally only as needed.")
        Text("Use History to delete generated GIF history and resumable job data from this device.")
      }

      Section("Messages") {
        Text("GifForge inserts a preview into Messages. You choose when to send it.")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Data Handling")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct DeveloperSettingsView: View {
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
      Section("Build") {
        LabeledContent("Version", value: "\(Self.appVersion) (\(Self.buildNumber))")
        LabeledContent("Bundle", value: Self.bundleIdentifier)
      }

      Section("Account State") {
        LabeledContent("User", value: userID ?? "Not created")
        LabeledContent("Kind", value: accountKind ?? "Unknown")
        LabeledContent("Recovery", value: recoveryProvider ?? "None")
        LabeledContent("App Account Token", value: appAccountToken?.uuidString ?? "Unavailable")
        if let creditBalance {
          LabeledContent("Available Credits", value: "\(creditBalance.availableCredits)")
          LabeledContent("Reserved Credits", value: "\(creditBalance.reservedCredits)")
        }
      }

      Section("Backend") {
        TextField("Base URL", text: $backendBaseURL)
          .textInputAutocapitalization(.never)
          .textContentType(.URL)
          .keyboardType(.URL)
          .autocorrectionDisabled()
        Toggle("Require App Attest", isOn: $backendRequiresAppAttest)
        LabeledContent(
          "App Attest Session",
          value: appAttestSessionIsReady ? "Ready" : "Not prepared"
        )
        if backendRequiresAppAttest {
          Button {
            refreshAppAttestSession()
          } label: {
            Label("Refresh App Attest Session", systemImage: "checkmark.shield")
          }
          .disabled(isPreparingAppAttest)
        }
      }

      Section("Diagnostics") {
        LabeledContent("Latest Message", value: settingsMessage ?? "None")
        Text("Run the local backend with dotnet run from the Backend project. Use your Mac LAN IP for device testing.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Developer")
    .navigationBarTitleDisplayMode(.inline)
  }

  private static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
  }

  private static var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }

  private static var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? "Unknown"
  }
}

private struct SettingsView: View {
  @AppStorage("backendBaseURL", store: gifforgeDefaults)
  private var backendBaseURL = "http://127.0.0.1:8787"
  @AppStorage("backendRequiresAppAttest", store: gifforgeDefaults)
  private var backendRequiresAppAttest = false
  @State private var userID: String?
  @State private var appAccountToken: UUID?
  @State private var accountKind: String?
  @State private var recoveryProvider: String?
  @State private var creditBalance: BackendCreditBalance?
  @State private var settingsMessage: String?
  @State private var isRefreshingAccount = false
  @State private var isPreparingAppAttest = false
  @State private var isLinkingAppleRecovery = false
  @State private var currentAppleSignInNonce: String?
  #if canImport(StoreKit)
  @State private var storeProducts: [Product] = []
  @State private var isPurchasing = false
  #endif

  private let tokenStore = KeychainBackendAuthTokenStore()
  private static let logger = Logger(subsystem: "dev.ericslutz.gifforge", category: "Settings")

  var body: some View {
    Form {
      Section("Account") {
        if userID != nil {
          LabeledContent("Account", value: accountKind == "appleLinked" ? "Recovery enabled" : "Local")
          if let creditBalance {
            LabeledContent("Available Credits", value: "\(creditBalance.availableCredits)")
          }
          Button {
            refreshAccount()
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(isRefreshingAccount)
          Button(role: .destructive) {
            tokenStore.clear()
            self.userID = nil
            appAccountToken = nil
            accountKind = nil
            recoveryProvider = nil
            creditBalance = nil
            #if canImport(StoreKit)
            storeProducts = []
            #endif
            Task {
              await restoreOrCreateAccount()
            }
          } label: {
            Label("Start New Local Account", systemImage: "rectangle.portrait.and.arrow.right")
          }
          .accessibilityHint("Clears this device's local GifForge account and creates a new one.")
        } else {
          HStack {
            ProgressView()
            Text("Preparing account")
              .foregroundStyle(.secondary)
          }
        }

        if let settingsMessage {
          Text(settingsMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if userID != nil {
        Section("Account Recovery") {
          LabeledContent("Apple", value: recoveryProvider == "apple" ? "Enabled" : "Not enabled")
          Text("Sign in with Apple is optional. Enable it to recover credits after reinstalling GifForge or moving to another device.")
            .font(.caption)
            .foregroundStyle(.secondary)
          if recoveryProvider != "apple" {
            SignInWithAppleButton(.continue) { request in
              request.requestedScopes = [.email]
              let nonce = Self.randomNonceString()
              currentAppleSignInNonce = nonce
              request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
              handleAppleRecovery(result)
            }
            .frame(height: 44)
            .disabled(isLinkingAppleRecovery || isPurchasing)
          }
        }
      }

      #if canImport(StoreKit)
      if appAccountToken != nil {
        Section("Credits") {
          if storeProducts.isEmpty {
            Button {
              refreshAccount()
            } label: {
              Label("Load Credit Packs", systemImage: "cart")
            }
          } else {
            ForEach(storeProducts, id: \.id) { product in
              Button {
                purchase(product)
              } label: {
                HStack {
                  Text(product.displayName)
                  Spacer()
                  Text(product.displayPrice)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      #endif

      Section("Privacy") {
        NavigationLink {
          PrivacyDetailsView()
        } label: {
          Label("Data Handling", systemImage: "hand.raised")
        }
      }

      Section("Developer") {
        NavigationLink {
          DeveloperSettingsView(
            backendBaseURL: $backendBaseURL,
            backendRequiresAppAttest: $backendRequiresAppAttest,
            userID: userID,
            appAccountToken: appAccountToken,
            accountKind: accountKind,
            recoveryProvider: recoveryProvider,
            creditBalance: creditBalance,
            settingsMessage: settingsMessage,
            isPreparingAppAttest: isPreparingAppAttest,
            appAttestSessionIsReady: sharedAppAttestSessionStore.loadValidToken() != nil,
            refreshAppAttestSession: prepareAppAttestSession
          )
        } label: {
          Label("Developer", systemImage: "hammer")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Settings")
    .task {
      await restoreOrCreateAccount()
      if backendRequiresAppAttest {
        await prepareAppAttestSessionIfNeeded()
      }
    }
    .onChange(of: backendRequiresAppAttest) { _, requiresAppAttest in
      if requiresAppAttest {
        prepareAppAttestSession()
      } else {
        sharedAppAttestSessionStore.clear()
      }
    }
  }

  private var baseURL: URL {
    URL(string: backendBaseURL) ?? URL(string: "http://127.0.0.1:8787")!
  }

  private func unauthenticatedClient() -> GifForgeBackendClient {
    GifForgeBackendClient(baseURL: baseURL)
  }

  private func authenticatedClient() -> GifForgeBackendClient {
    GifForgeBackendClient(
      baseURL: baseURL,
      authorizer: StoredBearerTokenAuthorizer(provider: tokenStore)
    )
  }

  private var sharedAppAttestSessionStore: SharedAppAttestSessionStore {
    SharedAppAttestSessionStore(defaults: gifforgeDefaults)
  }

  private func prepareAppAttestSession() {
    Task {
      await prepareAppAttestSessionIfNeeded(forceRefresh: true)
    }
  }

  private func prepareAppAttestSessionIfNeeded(forceRefresh: Bool = false) async {
    guard backendRequiresAppAttest else {
      return
    }

    if !forceRefresh, sharedAppAttestSessionStore.loadValidToken() != nil {
      return
    }

    isPreparingAppAttest = true
    defer { isPreparingAppAttest = false }

    do {
      let provider = DeviceCheckAppAttestSessionProvider(
        backendClient: unauthenticatedClient(),
        keyIDStore: AppAttestKeyIDStore(defaults: gifforgeDefaults),
        sessionStore: sharedAppAttestSessionStore
      )
      _ = try await provider.sessionToken()
      settingsMessage = "App Attest is ready for Messages."
    } catch {
      settingsMessage = error.gifforgeUserFacingMessage
    }
  }

  private func handleAppleRecovery(_ result: Result<ASAuthorization, Error>) {
    Task {
      isLinkingAppleRecovery = true
      defer { isLinkingAppleRecovery = false }
      do {
        let authorization: ASAuthorization
        switch result {
        case let .success(success):
          authorization = success
        case let .failure(error):
          currentAppleSignInNonce = nil
          let message = Self.appleSignInMessage(for: error)
          Self.logger.error("Sign in with Apple authorization failed: \(error.localizedDescription, privacy: .public)")
          settingsMessage = message
          return
        }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
          currentAppleSignInNonce = nil
          Self.logger.error("Sign in with Apple completed without an Apple ID credential.")
          settingsMessage = "Apple did not return an Apple ID credential. Try signing in again."
          return
        }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
          currentAppleSignInNonce = nil
          Self.logger.error("Sign in with Apple completed without an identity token.")
          settingsMessage = "Apple did not return an identity token. Try signing in again."
          return
        }

        if try tokenStore.load() == nil {
          settingsMessage = "Creating a local GifForge account..."
          let anonymous = try await unauthenticatedClient().createAnonymousSession()
          try tokenStore.save(session: anonymous)
        }

        #if canImport(StoreKit)
        if let appAccountToken {
          settingsMessage = "Checking unfinished purchases before enabling recovery..."
          let service = StoreKitCreditPurchaseService(
            backendClient: authenticatedClient(),
            appAccountToken: appAccountToken
          )
          _ = try await service.submitUnfinishedTransactions()
        }
        #endif

        settingsMessage = "Enabling Apple account recovery..."
        Self.logger.info("Sign in with Apple returned an identity token. Linking it for account recovery.")
        let session = try await authenticatedClient().linkSignInWithApple(
          identityToken: identityToken,
          nonce: currentAppleSignInNonce
        )
        currentAppleSignInNonce = nil
        try tokenStore.save(session: session)
        let profile = try await authenticatedClient().fetchMe()
        apply(profile)
        Self.logger.info("Apple account recovery enabled for backend user \(session.userID, privacy: .public).")
        await loadCreditsAndProducts(clearMessageOnSuccess: false)
        settingsMessage = "Apple account recovery is enabled."
      } catch {
        Self.logger.error("Sign in with Apple backend exchange failed: \(error.localizedDescription, privacy: .public)")
        settingsMessage = error.gifforgeUserFacingMessage
      }
    }
  }

  private static func appleSignInMessage(for error: Error) -> String {
    if let authorizationError = error as? ASAuthorizationError,
       authorizationError.code == .canceled {
      return "Sign in was canceled."
    }

    return "Apple sign-in failed before GifForge could contact the backend. Try again."
  }

  private func refreshAccount() {
    Task {
      await loadCreditsAndProducts()
    }
  }

  private func restoreOrCreateAccount() async {
    do {
      let existingSnapshot = try tokenStore.load()
      if let existingSnapshot {
        do {
          let profile = try await authenticatedClient().fetchMe()
          apply(profile)
          await loadCreditsAndProducts()
          return
        } catch {
          Self.logger.info("Stored backend access token could not load profile; trying refresh before creating a new local account.")
          do {
            let refreshed = try await unauthenticatedClient().refreshSession(refreshToken: existingSnapshot.refreshToken)
            try tokenStore.save(session: refreshed)
          } catch {
            Self.logger.info("Stored backend refresh token could not be refreshed; creating a new local account.")
            tokenStore.clear()
          }
        }
      }

      if try tokenStore.load() == nil {
        settingsMessage = "Creating a local GifForge account..."
        let session = try await unauthenticatedClient().createAnonymousSession()
        try tokenStore.save(session: session)
      }
      let profile = try await authenticatedClient().fetchMe()
      apply(profile)
      await loadCreditsAndProducts()
    } catch {
      settingsMessage = error.gifforgeUserFacingMessage
    }
  }

  private func apply(_ profile: BackendAccountProfile) {
    userID = profile.userID
    appAccountToken = profile.appAccountToken
    accountKind = profile.accountKind
    recoveryProvider = profile.recoveryProvider
  }

  private func loadCreditsAndProducts(clearMessageOnSuccess: Bool = true) async {
    isRefreshingAccount = true
    defer { isRefreshingAccount = false }
    do {
      let profile = try await authenticatedClient().fetchMe()
      apply(profile)
      creditBalance = try await authenticatedClient().fetchCreditBalance()
      #if canImport(StoreKit)
      if let appAccountToken {
        let service = StoreKitCreditPurchaseService(
          backendClient: authenticatedClient(),
          appAccountToken: appAccountToken
        )
        storeProducts = try await service.products()
      }
      #endif
      if clearMessageOnSuccess {
        settingsMessage = nil
      }
    } catch {
      settingsMessage = error.gifforgeUserFacingMessage
    }
  }

  #if canImport(StoreKit)
  private func purchase(_ product: Product) {
    Task {
      isPurchasing = true
      defer { isPurchasing = false }
      guard let appAccountToken else {
        settingsMessage = "GifForge is still creating your local account. Try again in a moment."
        return
      }
      do {
        let service = StoreKitCreditPurchaseService(
          backendClient: authenticatedClient(),
          appAccountToken: appAccountToken
        )
        _ = try await service.purchase(product)
        await loadCreditsAndProducts()
      } catch {
        settingsMessage = error.gifforgeUserFacingMessage
      }
    }
  }
  #endif

  private static func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var randomBytes = [UInt8](repeating: 0, count: length)
    let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
    guard status == errSecSuccess else {
      return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    for byte in randomBytes {
      result.append(charset[Int(byte) % charset.count])
    }
    return result
  }

  private static func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.map { String(format: "%02x", $0) }.joined()
  }
}
