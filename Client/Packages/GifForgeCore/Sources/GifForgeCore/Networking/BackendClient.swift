import Foundation

public struct GifForgeBackendClient: @unchecked Sendable {
  /// Shared session with explicit timeouts so a stalled backend fails fast inside the
  /// Messages extension instead of hanging on the platform defaults.
  public static let defaultSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    return URLSession(configuration: configuration)
  }()

  public var baseURL: URL
  public var session: URLSession
  public var encoder: JSONEncoder
  public var decoder: JSONDecoder
  public var authorizer: any BackendRequestAuthorizing

  public init(
    baseURL: URL,
    session: URLSession = GifForgeBackendClient.defaultSession,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder(),
    authorizer: any BackendRequestAuthorizing = NoopBackendRequestAuthorizer()
  ) {
    self.baseURL = baseURL
    self.session = session
    self.encoder = encoder
    self.decoder = decoder
    self.authorizer = authorizer
  }

  public func createJob(_ requestBody: StructuredGenerationRequest) async throws -> GenerationJob {
    var request = URLRequest(url: baseURL.appending(path: "/v1/generations"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(requestBody)

    let data = try await data(for: request)
    let response = try decoder.decode(JobSubmissionResponse.self, from: data)
    return GenerationJob(
      id: response.jobId,
      status: response.status,
      statusURL: response.statusUrl,
      expiresAt: response.expiresAt,
      requiredCredits: response.requiredCredits
    )
  }

  public func createAppAttestChallenge() async throws -> AppAttestChallenge {
    var request = URLRequest(url: baseURL.appending(path: "/v1/app-attest/challenges"))
    request.httpMethod = "POST"

    let data = try await data(for: request)
    return try decoder.decode(AppAttestChallenge.self, from: data)
  }

  public func createAppAttestSession(_ requestBody: AppAttestAttestationRequest) async throws -> AppAttestSession {
    var request = URLRequest(url: baseURL.appending(path: "/v1/app-attest/attestations"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(requestBody)

    let data = try await data(for: request)
    return try decoder.decode(AppAttestSession.self, from: data)
  }

  public func signInWithApple(identityToken: String, nonce: String?) async throws -> BackendAuthSession {
    var request = URLRequest(url: baseURL.appending(path: "/v1/auth/apple"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(AppleAuthRequest(identityToken: identityToken, nonce: nonce))

    do {
      let data = try await responseData(for: request, applyAuthorizer: false).0
      return try decoder.decode(BackendAuthSession.self, from: data)
    } catch let GifForgeError.backendRejected(statusCode, _) where statusCode == 401 || statusCode == 403 {
      throw GifForgeError.appleSignInFailed(message: "GifForge could not verify your Apple sign-in with the backend. Try again.")
    }
  }

  public func createAnonymousSession() async throws -> BackendAuthSession {
    var request = URLRequest(url: baseURL.appending(path: "/v1/auth/anonymous"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)

    let data = try await responseData(for: request, applyAuthorizer: false).0
    return try decoder.decode(BackendAuthSession.self, from: data)
  }

  public func refreshSession(refreshToken: String) async throws -> BackendAuthSession {
    var request = URLRequest(url: baseURL.appending(path: "/v1/auth/refresh"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(RefreshTokenRequest(refreshToken: refreshToken))

    let data = try await responseData(for: request, applyAuthorizer: false).0
    return try decoder.decode(BackendAuthSession.self, from: data)
  }

  public func linkSignInWithApple(identityToken: String, nonce: String?) async throws -> BackendAuthSession {
    var request = URLRequest(url: baseURL.appending(path: "/v1/auth/apple/link"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(AppleAuthRequest(identityToken: identityToken, nonce: nonce))

    do {
      let data = try await data(for: request)
      return try decoder.decode(BackendAuthSession.self, from: data)
    } catch let GifForgeError.backendRejected(statusCode, _) where statusCode == 401 || statusCode == 403 {
      throw GifForgeError.appleSignInFailed(message: "GifForge could not enable Apple account recovery. Try again.")
    }
  }

  public func fetchMe() async throws -> BackendAccountProfile {
    let request = URLRequest(url: baseURL.appending(path: "/v1/me"))
    let data = try await data(for: request)
    return try decoder.decode(BackendAccountProfile.self, from: data)
  }

  public func fetchCreditBalance() async throws -> BackendCreditBalance {
    let request = URLRequest(url: baseURL.appending(path: "/v1/me/credits"))
    let data = try await data(for: request)
    return try decoder.decode(BackendCreditBalance.self, from: data)
  }

  public func fetchIAPProducts() async throws -> [BackendIAPProduct] {
    let request = URLRequest(url: baseURL.appending(path: "/v1/iap/products"))
    let data = try await data(for: request)
    return try decoder.decode(BackendIAPProductsResponse.self, from: data).products
  }

  public func submitIAPTransaction(
    productID: String,
    signedTransaction: String
  ) async throws -> BackendIAPTransactionResult {
    var request = URLRequest(url: baseURL.appending(path: "/v1/iap/transactions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(IAPTransactionSubmissionRequest(
      productID: productID,
      signedTransaction: signedTransaction
    ))

    let data = try await data(for: request)
    return try decoder.decode(BackendIAPTransactionResult.self, from: data)
  }

  public func fetchJobStatus(statusURL: URL) async throws -> GenerationJob {
    let request = URLRequest(url: statusURL)
    let data = try await data(for: request)
    let response = try decoder.decode(JobStatusResponse.self, from: data)
    return GenerationJob(
      id: response.jobId,
      status: response.status,
      statusURL: statusURL,
      downloadURL: response.downloadUrl,
      message: response.message,
      expiresAt: response.expiresAt,
      retryAvailable: response.retryAvailable ?? false,
      retryReason: response.retryReason,
      retryOfJobId: response.retryOfJobId
    )
  }

  public func downloadFrameSequence(from url: URL) async throws -> FrameSequenceAsset {
    let request = URLRequest(url: url)
    let data = try await data(for: request)
    return try decoder.decode(FrameSequenceAsset.self, from: data)
  }

  public func downloadMotionAsset(from url: URL) async throws -> GeneratedMotionAsset {
    let request = URLRequest(url: url)
    let (data, response) = try await responseData(for: request)
    let contentType = response
      .value(forHTTPHeaderField: "Content-Type")?
      .lowercased() ?? ""

    if contentType.contains("video/mp4") {
      let destinationURL = FileManager.default.temporaryDirectory
        .appending(path: "GifForge-\(UUID().uuidString).mp4")
      try data.write(to: destinationURL, options: [.atomic])
      return .mp4(destinationURL)
    }

    return .frameSequence(try decoder.decode(FrameSequenceAsset.self, from: data))
  }

  private func data(for request: URLRequest) async throws -> Data {
    try await responseData(for: request).0
  }

  private func responseData(
    for request: URLRequest,
    applyAuthorizer: Bool = true
  ) async throws -> (Data, HTTPURLResponse) {
    let result = try await performOnce(request: request, applyAuthorizer: applyAuthorizer)
    guard result.1.statusCode == 401,
          applyAuthorizer,
          let recovering = authorizer as? any BackendAuthorizationRecovering,
          await recovering.recoverAuthorization(afterStatusCode: 401)
    else {
      return try validated(result)
    }

    return try validated(await performOnce(request: request, applyAuthorizer: true))
  }

  private func performOnce(
    request: URLRequest,
    applyAuthorizer: Bool
  ) async throws -> (Data, HTTPURLResponse) {
    let authorizedRequest = applyAuthorizer
      ? try await authorizer.authorizedRequest(for: request)
      : request
    let (data, response) = try await session.data(for: authorizedRequest)
    guard let http = response as? HTTPURLResponse else {
      throw GifForgeError.backendRejected(statusCode: -1, message: "Backend did not return an HTTP response.")
    }

    return (data, http)
  }

  private func validated(_ result: (Data, HTTPURLResponse)) throws -> (Data, HTTPURLResponse) {
    let (data, http) = result
    guard (200..<300).contains(http.statusCode) else {
      throw GifForgeError.backendRejected(statusCode: http.statusCode, message: Self.serverMessage(from: data))
    }

    return (data, http)
  }

  /// Extracts a short server-authored message from a structured error body; anything
  /// else (HTML pages, stack traces, oversized payloads) is dropped rather than shown.
  static func serverMessage(from data: Data) -> String {
    struct ErrorBody: Decodable {
      var message: String?
      var error: String?
    }

    if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
      let candidate = body.message ?? body.error ?? ""
      if !candidate.isEmpty, candidate.count <= 300 {
        return candidate
      }
    }

    return ""
  }
}
