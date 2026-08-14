import Foundation

public enum GifForgeError: Error, Equatable, LocalizedError, Sendable {
  case emptyPrompt
  case invalidCaption(reason: String)
  case invalidImage
  case backendRejected(statusCode: Int, message: String)
  case appleSignInFailed(message: String)
  case appAttestUnavailable
  case localModelUnavailable
  case jobFailed(message: String)
  case retryAvailable(GenerationJob, String)
  case jobTimedOut
  case mediaRenderingFailed(message: String)
  case storageFailed(message: String)
  case gifTooLarge(byteCount: Int, limit: Int)
  case sourceMediaTooLarge(byteCount: Int, limit: Int)
  case accountSessionMissing
  /// The on-device model refused the prompt on safety grounds. Deliberately
  /// distinct from every other planning failure: those fall back to the
  /// deterministic template planner, but a guardrail refusal must not be
  /// silently routed around — the user needs to actually change the prompt.
  case promptRejected(explanation: String?)

  public var errorDescription: String? {
    switch self {
    case .emptyPrompt:
      "Enter a prompt before generating a GIF."
    case let .invalidCaption(reason):
      reason
    case .invalidImage:
      "The selected image could not be processed."
    case .backendRejected:
      userFacingMessage
    case let .appleSignInFailed(message):
      message
    case .appAttestUnavailable:
      userFacingMessage
    case .localModelUnavailable:
      userFacingMessage
    case let .jobFailed(message):
      message
    case let .retryAvailable(_, message):
      message
    case .jobTimedOut:
      "The generation took too long. You can reopen GifForge and resume the job."
    case let .mediaRenderingFailed(message):
      message
    case let .storageFailed(message):
      message
    case .gifTooLarge:
      userFacingMessage
    case .sourceMediaTooLarge:
      userFacingMessage
    case .accountSessionMissing:
      userFacingMessage
    case .promptRejected:
      userFacingMessage
    }
  }

  public var userFacingMessage: String {
    switch self {
    case .emptyPrompt:
      "Enter a prompt before generating a GIF."
    case let .invalidCaption(reason):
      reason
    case .invalidImage:
      "The selected image could not be processed. Try a different image."
    case let .backendRejected(statusCode, message):
      BackendErrorMessage(statusCode: statusCode, rawMessage: message).userFacingMessage
    case let .appleSignInFailed(message):
      message.isEmpty ? "Sign in with Apple could not be completed. Try again." : message
    case .appAttestUnavailable:
      "This backend requires App Attest, which is not available here. Try again on a supported physical device."
    case .localModelUnavailable:
      "Local Apple models are unavailable, so GifForge will use its built-in prompt planner."
    case let .jobFailed(message):
      message.isEmpty ? "The GIF generation failed. Try again with a different prompt." : message
    case let .retryAvailable(_, message):
      message.isEmpty ? "Generation failed. You can try again with another provider." : message
    case .jobTimedOut:
      "The generation took too long. You can reopen GifForge and resume the job."
    case let .mediaRenderingFailed(message):
      message
    case let .storageFailed(message):
      message
    case .gifTooLarge:
      "The GIF is too large for Messages. Try a shorter or simpler prompt."
    case let .sourceMediaTooLarge(_, limit):
      "That video or GIF is too large to send (limit about \(limit / 1_000_000)MB). Try a shorter clip."
    case .accountSessionMissing:
      "Open the GifForge app once to finish setup, then come back to Messages."
    case let .promptRejected(explanation):
      explanation?.isEmpty == false
        ? "That prompt can't be generated: \(explanation!). Try rewording it."
        : "That prompt can't be generated. Try rewording it."
    }
  }
}

private struct BackendErrorMessage {
  var statusCode: Int
  var rawMessage: String

  var userFacingMessage: String {
    if statusCode == -1 {
      return "GifForge could not read the backend response. Try again."
    }

    if statusCode == 401 || statusCode == 403 {
      return "GifForge could not verify this app with the backend. Try again on a supported physical device."
    }

    if statusCode == 408 || statusCode == 429 || statusCode >= 500 {
      return "The GIF generator is temporarily unavailable. Try again in a few minutes."
    }

    if statusCode == 413 {
      return "That image or request is too large. Try a smaller image or shorter prompt."
    }

    let normalized = rawMessage.lowercased()
    if statusCode == 422 ||
        normalized.contains("moderation") ||
        normalized.contains("safety") {
      return "That request cannot be generated. Try changing the prompt or selected image."
    }

    // Only surface server-authored one-liners; never dump long or markup-looking
    // bodies (HTML error pages, stack traces) into a user-facing alert.
    let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, trimmed.count <= 160, !trimmed.contains("<") {
      return trimmed
    }

    return "GifForge could not complete that request. Try again."
  }
}

public extension Error {
  var gifforgeUserFacingMessage: String {
    if let gifforgeError = self as? GifForgeError {
      return gifforgeError.userFacingMessage
    }

    if let urlError = self as? URLError {
      return urlError.gifforgeUserFacingMessage
    }

    return localizedDescription
  }
}

public extension URLError {
  var gifforgeUserFacingMessage: String {
    switch code {
    case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut:
      "GifForge could not reach the backend. Check your connection and try again."
    case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
      "GifForge could not establish a secure connection to the backend."
    default:
      "GifForge could not reach the backend. Try again."
    }
  }
}
