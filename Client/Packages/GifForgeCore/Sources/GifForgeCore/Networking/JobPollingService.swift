import Foundation

public actor JobPollingService {
  private let client: GifForgeBackendClient

  public init(client: GifForgeBackendClient) {
    self.client = client
  }

  public func waitForCompletion(
    startingWith job: GenerationJob,
    timeoutSeconds: Double = 90,
    pollIntervalSeconds: Double = 1.5,
    maxPollIntervalSeconds: Double = 6.0
  ) async throws -> GenerationJob {
    var deadline = Date().addingTimeInterval(timeoutSeconds)
    if let expiration = job.expirationDate, expiration < deadline {
      deadline = expiration
    }

    var current = job
    var interval = pollIntervalSeconds

    while Date() < deadline {
      try Task.checkCancellation()
      current = try await client.fetchJobStatus(statusURL: current.statusURL)

      switch current.status {
      case .succeeded:
        return current
      case .failed:
        if current.retryAvailable {
          throw GifForgeError.retryAvailable(current, current.message ?? "Generation failed. You can try again with another provider.")
        }

        throw GifForgeError.jobFailed(message: current.message ?? "Generation failed.")
      case .queued, .running:
        // Exponential backoff with jitter keeps long-running jobs from hammering the
        // backend at a fixed rate while staying responsive for fast jobs.
        let jitter = Double.random(in: 0...(interval * 0.2))
        try await Task.sleep(nanoseconds: UInt64((interval + jitter) * 1_000_000_000))
        interval = min(maxPollIntervalSeconds, interval * 1.5)
      }
    }

    throw GifForgeError.jobTimedOut
  }
}
