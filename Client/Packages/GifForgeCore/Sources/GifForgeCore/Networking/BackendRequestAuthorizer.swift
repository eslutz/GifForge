import Foundation

public protocol BackendRequestAuthorizing: Sendable {
  func authorizedRequest(for request: URLRequest) async throws -> URLRequest
}

/// Authorizers that can repair their credentials after an authorization failure
/// (for example by redeeming a refresh token). Returning `true` asks the client
/// to retry the original request exactly once.
public protocol BackendAuthorizationRecovering: Sendable {
  func recoverAuthorization(afterStatusCode statusCode: Int) async -> Bool
}

public struct NoopBackendRequestAuthorizer: BackendRequestAuthorizing {
  public init() {}

  public func authorizedRequest(for request: URLRequest) async throws -> URLRequest {
    request
  }
}

public struct StaticBearerTokenAuthorizer: BackendRequestAuthorizing {
  public var token: String

  public init(token: String) {
    self.token = token
  }

  public func authorizedRequest(for request: URLRequest) async throws -> URLRequest {
    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }
}

public struct CompositeBackendRequestAuthorizer: BackendRequestAuthorizing, BackendAuthorizationRecovering {
  public var authorizers: [any BackendRequestAuthorizing]

  public init(authorizers: [any BackendRequestAuthorizing]) {
    self.authorizers = authorizers
  }

  public func authorizedRequest(for request: URLRequest) async throws -> URLRequest {
    var authorized = request
    for authorizer in authorizers {
      authorized = try await authorizer.authorizedRequest(for: authorized)
    }
    return authorized
  }

  public func recoverAuthorization(afterStatusCode statusCode: Int) async -> Bool {
    var recovered = false
    for authorizer in authorizers {
      if let recovering = authorizer as? any BackendAuthorizationRecovering,
         await recovering.recoverAuthorization(afterStatusCode: statusCode) {
        recovered = true
      }
    }
    return recovered
  }
}

public protocol BackendAccessTokenProviding: Sendable {
  func accessToken() async throws -> String?
}

public struct StoredBearerTokenAuthorizer: BackendRequestAuthorizing {
  private let provider: any BackendAccessTokenProviding

  public init(provider: any BackendAccessTokenProviding) {
    self.provider = provider
  }

  public func authorizedRequest(for request: URLRequest) async throws -> URLRequest {
    guard let token = try await provider.accessToken(), !token.isEmpty else {
      return request
    }

    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }
}
