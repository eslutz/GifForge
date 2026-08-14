import CoreGraphics
import Foundation
import Testing
@testable import GifForgeCore

private final class InMemorySessionStore: BackendAuthSessionStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var snapshot: BackendAuthTokenSnapshot?

  init(session: BackendAuthSession?) {
    snapshot = session.map(BackendAuthTokenSnapshot.init(session:))
  }

  func load() throws -> BackendAuthTokenSnapshot? {
    lock.withLock { snapshot }
  }

  func save(session: BackendAuthSession) throws {
    lock.withLock { snapshot = BackendAuthTokenSnapshot(session: session) }
  }
}

private func makeSession(
  accessToken: String,
  accessExpiresAt: Date,
  refreshToken: String = "refresh-1",
  refreshExpiresAt: Date = Date().addingTimeInterval(60 * 60)
) -> BackendAuthSession {
  let formatter = ISO8601DateFormatter()
  return BackendAuthSession(
    userID: "user-1",
    appAccountToken: UUID(),
    accessToken: accessToken,
    accessTokenExpiresAt: formatter.string(from: accessExpiresAt),
    refreshToken: refreshToken,
    refreshTokenExpiresAt: formatter.string(from: refreshExpiresAt)
  )
}

private func refreshedSessionJSON(accessToken: String) -> Data {
  let formatter = ISO8601DateFormatter()
  let future = formatter.string(from: Date().addingTimeInterval(15 * 60))
  return Data("""
  {
    "userId": "user-1",
    "appAccountToken": "\(UUID().uuidString)",
    "accessToken": "\(accessToken)",
    "accessTokenExpiresAt": "\(future)",
    "refreshToken": "refresh-2",
    "refreshTokenExpiresAt": "\(future)"
  }
  """.utf8)
}

@Suite("Refreshing bearer authorizer")
struct RefreshingBearerTokenAuthorizerTests {
  @Test("Expiring access token is refreshed before the request is sent")
  func proactiveRefresh() async throws {
    final class MockProtocol: URLProtocol {
      nonisolated(unsafe) static var refreshCalls = 0

      override static func canInit(with request: URLRequest) -> Bool { true }
      override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
      override func stopLoading() {}

      override func startLoading() {
        guard request.url?.path.hasSuffix("/v1/auth/refresh") == true else {
          fatalError("Unexpected request: \(String(describing: request.url))")
        }

        Self.refreshCalls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: refreshedSessionJSON(accessToken: "fresh-token"))
        client?.urlProtocolDidFinishLoading(self)
      }
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockProtocol.self]
    let session = URLSession(configuration: configuration)

    let store = InMemorySessionStore(session: makeSession(
      accessToken: "stale-token",
      accessExpiresAt: Date().addingTimeInterval(-60)
    ))
    let authorizer = RefreshingBearerTokenAuthorizer(
      store: store,
      baseURL: URL(string: "https://example.test")!,
      session: session
    )

    let request = try await authorizer.authorizedRequest(for: URLRequest(url: URL(string: "https://example.test/v1/me")!))

    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token")
    #expect(MockProtocol.refreshCalls == 1)
    #expect(try store.load()?.accessToken == "fresh-token")
  }

  @Test("A 401 triggers one refresh-and-retry through the backend client")
  func recoveryRetriesOnce() async throws {
    final class MockProtocol: URLProtocol {
      nonisolated(unsafe) static var meCalls = 0
      nonisolated(unsafe) static var refreshCalls = 0
      nonisolated(unsafe) static var lastAuthorization: String?

      override static func canInit(with request: URLRequest) -> Bool { true }
      override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
      override func stopLoading() {}

      override func startLoading() {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/v1/auth/refresh") {
          Self.refreshCalls += 1
          let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: refreshedSessionJSON(accessToken: "recovered-token"))
          client?.urlProtocolDidFinishLoading(self)
          return
        }

        Self.meCalls += 1
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        if Self.meCalls == 1 {
          let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: Data("{\"error\":\"expired_token\"}".utf8))
        } else {
          let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
          let profile = Data("""
          {"userId": "user-1", "appAccountToken": "\(UUID().uuidString)", "accountKind": "anonymous"}
          """.utf8)
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: profile)
        }
        client?.urlProtocolDidFinishLoading(self)
      }
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockProtocol.self]
    let session = URLSession(configuration: configuration)

    let store = InMemorySessionStore(session: makeSession(
      accessToken: "rejected-token",
      accessExpiresAt: Date().addingTimeInterval(10 * 60)
    ))
    let authorizer = RefreshingBearerTokenAuthorizer(
      store: store,
      baseURL: URL(string: "https://example.test")!,
      session: session
    )
    let client = GifForgeBackendClient(
      baseURL: URL(string: "https://example.test")!,
      session: session,
      authorizer: authorizer
    )

    let profile = try await client.fetchMe()

    #expect(profile.accountKind == "anonymous")
    #expect(MockProtocol.meCalls == 2)
    #expect(MockProtocol.refreshCalls == 1)
    #expect(MockProtocol.lastAuthorization == "Bearer recovered-token")
  }

  @Test("Without a stored session requests pass through unauthenticated")
  func missingSessionPassesThrough() async throws {
    let authorizer = RefreshingBearerTokenAuthorizer(
      store: InMemorySessionStore(session: nil),
      baseURL: URL(string: "https://example.test")!
    )

    let request = try await authorizer.authorizedRequest(for: URLRequest(url: URL(string: "https://example.test/v1/generations")!))

    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }
}

@Suite("Source media builder")
struct SourceMediaBuilderTests {
  @Test("Builds SourceMedia from picked GIF bytes")
  func buildsFromGIFBytes() throws {
    let media = try SourceMediaBuilder.makeSourceMedia(
      data: Data("GIF89a".utf8),
      mimeType: "image/gif",
      fileName: "clip.gif"
    )

    #expect(media.mimeType == "image/gif")
    #expect(media.fileName == "clip.gif")
    #expect(media.dataBase64 == Data("GIF89a".utf8).base64EncodedString())
  }

  @Test("Rejects media over the decoded size budget")
  func rejectsOversizedMedia() {
    let oversized = Data(count: SourceMediaBuilder.maxDecodedBytes + 1)

    #expect(throws: GifForgeError.self) {
      try SourceMediaBuilder.makeSourceMedia(data: oversized, mimeType: "video/mp4")
    }
  }

  @Test("Accepts media exactly at the size budget")
  func acceptsAtBudget() throws {
    let atLimit = Data(count: SourceMediaBuilder.maxDecodedBytes)
    let media = try SourceMediaBuilder.makeSourceMedia(data: atLimit, mimeType: "video/quicktime")
    #expect(media.mimeType == "video/quicktime")
  }
}

@Suite("GIF encode ladder")
struct GIFEncodeLadderTests {
  private func makeFrames() throws -> [GIFFrame] {
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: 100,
        height: 100,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw GifForgeError.mediaRenderingFailed(message: "test context")
    }

    var frames: [GIFFrame] = []
    for step in 0..<4 {
      context.setFillColor(CGColor(red: Double(step) * 0.2, green: 0.4, blue: 0.6, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
      guard let image = context.makeImage() else {
        throw GifForgeError.mediaRenderingFailed(message: "test frame")
      }
      frames.append(GIFFrame(image: image, duration: 0.1))
    }
    return frames
  }

  @Test("Ladder steps down to a smaller encode when the first exceeds its byte cap")
  func ladderStepsDown() throws {
    let frames = try makeFrames()
    let destination = FileManager.default.temporaryDirectory
      .appending(path: "GifForge-ladder-\(UUID().uuidString).gif")
    defer { try? FileManager.default.removeItem(at: destination) }

    let ladder = [
      GIFRenderOptions(maxPixelDimension: 100, maxFrameCount: 4, maxFileSizeBytes: 10),
      GIFRenderOptions(maxPixelDimension: 40, maxFrameCount: 2, maxFileSizeBytes: 1_000_000)
    ]

    let url = try GIFRenderer().render(frames: frames, to: destination, optionsLadder: ladder)

    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test("Ladder rethrows when no rung fits")
  func ladderRethrowsWhenNothingFits() throws {
    let frames = try makeFrames()
    let destination = FileManager.default.temporaryDirectory
      .appending(path: "GifForge-ladder-\(UUID().uuidString).gif")
    defer { try? FileManager.default.removeItem(at: destination) }

    let ladder = [GIFRenderOptions(maxPixelDimension: 100, maxFrameCount: 4, maxFileSizeBytes: 10)]

    #expect(throws: GifForgeError.self) {
      try GIFRenderer().render(frames: frames, to: destination, optionsLadder: ladder)
    }
    #expect(FileManager.default.fileExists(atPath: destination.path) == false)
  }
}
