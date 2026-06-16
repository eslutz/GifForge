import Foundation
import Testing
@testable import GifForgeCore

@Suite("Job polling")
struct JobPollingServiceTests {
  @Test("Retryable failed jobs throw retry-available error")
  func retryableFailureThrowsRetryAvailable() async throws {
    final class MockProtocol: URLProtocol {
      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        let body = """
        {
          "jobId": "job-1",
          "status": "failed",
          "downloadUrl": null,
          "message": "Generation provider reported failure.",
          "expiresAt": "2026-06-16T12:00:00Z",
          "retryAvailable": true,
          "retryReason": "provider_failed",
          "retryOfJobId": "job-1"
        }
        """.data(using: .utf8)!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
      }

      override func stopLoading() {}
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockProtocol.self]
    let client = GifForgeBackendClient(
      baseURL: URL(string: "https://example.test")!,
      session: URLSession(configuration: configuration)
    )

    do {
      _ = try await JobPollingService(client: client).waitForCompletion(
        startingWith: GenerationJob(
          id: "job-1",
          status: .running,
          statusURL: URL(string: "https://example.test/v1/generations/job-1")!
        ),
        timeoutSeconds: 1,
        pollIntervalSeconds: 0.01
      )
      Issue.record("Expected retry-available failure.")
    } catch let error as GifForgeError {
      guard case let .retryAvailable(job, message) = error else {
        Issue.record("Expected retryAvailable, got \(error).")
        return
      }

      #expect(job.retryOfJobId == "job-1")
      #expect(message == "Generation provider reported failure.")
    }
  }
}
