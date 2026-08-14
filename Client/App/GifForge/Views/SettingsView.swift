import GifForgeCore
import AuthenticationServices
import CryptoKit
import OSLog
import Security
import SwiftUI
#if canImport(StoreKit)
import StoreKit
#endif

struct SettingsView: View {
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
  @State private var isConfirmingNewLocalAccount = false
  #if canImport(StoreKit)
  @State private var storeProducts: [Product] = []
  @State private var isPurchasing = false
  #endif

  private let tokenStore = KeychainBackendAuthTokenStore()
  private static let logger = Logger(subsystem: "dev.ericslutz.gifforge", category: "Settings")

  var body: some View {
    Form {
      Section(String(localized: "Account")) {
        if userID != nil {
          LabeledContent(String(localized: "Account"), value: accountKind == "appleLinked" ? String(localized: "Recovery enabled") : String(localized: "Local"))
          if let creditBalance {
            LabeledContent(String(localized: "Available Credits"), value: "\(creditBalance.availableCredits)")
          }
          Button {
            refreshAccount()
          } label: {
            Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
          }
          .disabled(isRefreshingAccount)
          Button(role: .destructive) {
            isConfirmingNewLocalAccount = true
          } label: {
            Label(String(localized: "Start New Local Account"), systemImage: "rectangle.portrait.and.arrow.right")
          }
          .accessibilityHint(String(localized: "Clears this device's local GifForge account and creates a new one."))
          .alert(String(localized: "Start a new local account?"), isPresented: $isConfirmingNewLocalAccount) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Start New Account"), role: .destructive) {
              startNewLocalAccount()
            }
          } message: {
            Text(String(localized: "This signs out the current local account. Credits on it stay recoverable only if Apple account recovery was enabled."))
          }
        } else {
          HStack {
            ProgressView()
            Text(String(localized: "Preparing account"))
              .foregroundStyle(.primary)
          }
        }

        if let settingsMessage {
          Text(settingsMessage)
            .font(.caption)
            .foregroundStyle(.primary)
        }
      }

      if userID != nil {
        Section(String(localized: "Account Recovery")) {
          LabeledContent(String(localized: "Apple"), value: recoveryProvider == "apple" ? String(localized: "Enabled") : String(localized: "Not enabled"))
          Text(String(localized: "Sign in with Apple is optional. Enable it to recover credits after reinstalling GifForge or moving to another device."))
            .font(.caption)
            .foregroundStyle(.primary)
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
        Section(String(localized: "Credits")) {
          if storeProducts.isEmpty {
            Button {
              refreshAccount()
            } label: {
              Label(String(localized: "Load Credit Packs"), systemImage: "cart")
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
                    .foregroundStyle(.primary)
                }
              }
            }
          }
        }
      }
      #endif

      Section(String(localized: "Privacy")) {
        NavigationLink {
          PrivacyDetailsView()
        } label: {
          Label(String(localized: "Data Handling"), systemImage: "hand.raised")
        }
      }

      Section(String(localized: "Developer")) {
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
          Label(String(localized: "Developer"), systemImage: "hammer")
        }
      }
    }
    .formStyle(.grouped)
    .labeledContentStyle(PrimaryValueLabeledContentStyle())
    .navigationTitle(String(localized: "Settings"))
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
      settingsMessage = String(localized: "App Attest is ready for Messages.")
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
          settingsMessage = String(localized: "Apple did not return an Apple ID credential. Try signing in again.")
          return
        }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
          currentAppleSignInNonce = nil
          Self.logger.error("Sign in with Apple completed without an identity token.")
          settingsMessage = String(localized: "Apple did not return an identity token. Try signing in again.")
          return
        }

        if try tokenStore.load() == nil {
          settingsMessage = String(localized: "Creating a local GifForge account...")
          let anonymous = try await unauthenticatedClient().createAnonymousSession()
          try tokenStore.save(session: anonymous)
        }

        #if canImport(StoreKit)
        if let appAccountToken {
          settingsMessage = String(localized: "Checking unfinished purchases before enabling recovery...")
          let service = StoreKitCreditPurchaseService(
            backendClient: authenticatedClient(),
            appAccountToken: appAccountToken
          )
          _ = try await service.submitUnfinishedTransactions()
        }
        #endif

        settingsMessage = String(localized: "Enabling Apple account recovery...")
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
        settingsMessage = String(localized: "Apple account recovery is enabled.")
      } catch {
        Self.logger.error("Sign in with Apple backend exchange failed: \(error.localizedDescription, privacy: .public)")
        settingsMessage = error.gifforgeUserFacingMessage
      }
    }
  }

  private static func appleSignInMessage(for error: Error) -> String {
    if let authorizationError = error as? ASAuthorizationError,
       authorizationError.code == .canceled {
      return String(localized: "Sign in was canceled.")
    }

    return String(localized: "Apple sign-in failed before GifForge could contact the backend. Try again.")
  }

  private func refreshAccount() {
    Task {
      await loadCreditsAndProducts()
    }
  }

  private func startNewLocalAccount() {
    tokenStore.clear()
    userID = nil
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
        settingsMessage = String(localized: "Creating a local GifForge account...")
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
        settingsMessage = String(localized: "GifForge is still creating your local account. Try again in a moment.")
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
