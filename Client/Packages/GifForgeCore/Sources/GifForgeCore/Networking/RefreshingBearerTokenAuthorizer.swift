import Foundation

/// Bearer authorizer that keeps the stored backend session usable on its own:
/// it refreshes the access token before it expires and can recover from a 401
/// by redeeming the refresh token, so the Messages extension no longer strands
/// the user until the containing app is opened.
///
/// With no stored session it passes requests through unauthenticated, which
/// keeps the local demo-bypass backend flow working.
public actor RefreshingBearerTokenAuthorizer: BackendRequestAuthorizing, BackendAuthorizationRecovering {
  private let store: any BackendAuthSessionStoring
  private let baseURL: URL
  private let session: URLSession
  private let expiryMargin: TimeInterval
  private var refreshInFlight: Task<BackendAuthSession, Error>?

  public init(
    store: any BackendAuthSessionStoring = KeychainBackendAuthTokenStore(),
    baseURL: URL,
    session: URLSession = GifForgeBackendClient.defaultSession,
    expiryMargin: TimeInterval = 60
  ) {
    self.store = store
    self.baseURL = baseURL
    self.session = session
    self.expiryMargin = expiryMargin
  }

  public func authorizedRequest(for request: URLRequest) async throws -> URLRequest {
    guard let snapshot = try? store.load() else {
      return request
    }

    var token = snapshot.accessToken
    if isExpiring(snapshot.accessTokenExpiresAt), canRefresh(snapshot) {
      if let refreshed = try? await refreshSession(using: snapshot.refreshToken) {
        token = refreshed.accessToken
      }
    }

    guard !token.isEmpty else {
      return request
    }

    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }

  public func recoverAuthorization(afterStatusCode statusCode: Int) async -> Bool {
    guard statusCode == 401,
          let snapshot = try? store.load(),
          canRefresh(snapshot)
    else {
      return false
    }

    do {
      _ = try await refreshSession(using: snapshot.refreshToken)
      return true
    } catch {
      return false
    }
  }

  private func isExpiring(_ expiresAt: String) -> Bool {
    guard let expiration = GifForgeISO8601DateParser.date(from: expiresAt) else {
      return false
    }

    return expiration.timeIntervalSinceNow < expiryMargin
  }

  private func canRefresh(_ snapshot: BackendAuthTokenSnapshot) -> Bool {
    guard !snapshot.refreshToken.isEmpty else {
      return false
    }

    guard let expiration = GifForgeISO8601DateParser.date(from: snapshot.refreshTokenExpiresAt) else {
      return true
    }

    return expiration.timeIntervalSinceNow > 0
  }

  private func refreshSession(using refreshToken: String) async throws -> BackendAuthSession {
    if let refreshInFlight {
      return try await refreshInFlight.value
    }

    let task = Task { [baseURL, session] () throws -> BackendAuthSession in
      var request = URLRequest(url: baseURL.appending(path: "/v1/auth/refresh"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(RefreshTokenRequest(refreshToken: refreshToken))

      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw GifForgeError.backendRejected(statusCode: statusCode, message: GifForgeBackendClient.serverMessage(from: data))
      }

      return try JSONDecoder().decode(BackendAuthSession.self, from: data)
    }

    refreshInFlight = task
    defer { refreshInFlight = nil }

    let refreshed = try await task.value
    try store.save(session: refreshed)
    return refreshed
  }
}
