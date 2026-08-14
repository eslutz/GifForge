import Foundation

/// Whether the most recent (or next) planning call will run on Apple's on-device
/// model, versus fall back to the deterministic template planner, and why.
public enum PlannerAvailability: Equatable, Sendable {
  case onDevice
  case unavailable(PlannerUnavailableReason)

  public var isOnDevice: Bool {
    self == .onDevice
  }
}

public enum PlannerUnavailableReason: Equatable, Sendable {
  /// The device's hardware does not support Apple Intelligence.
  case deviceNotEligible
  /// Apple Intelligence is supported but the user has not turned it on.
  case appleIntelligenceNotEnabled
  /// Apple Intelligence is enabled but the on-device model assets are not
  /// finished downloading/preparing yet.
  case modelNotReady
  /// Running on an OS version older than Foundation Models requires.
  case osVersionTooOld
  /// The FoundationModels framework is not present at all on this platform
  /// (for example an unsupported build target).
  case frameworkUnavailable

  public var displayMessage: String {
    switch self {
    case .deviceNotEligible:
      "This device doesn't support Apple Intelligence."
    case .appleIntelligenceNotEnabled:
      "Turn on Apple Intelligence in Settings to plan GIFs on-device."
    case .modelNotReady:
      "Apple Intelligence is still preparing on this device."
    case .osVersionTooOld:
      "Update iOS to plan GIFs on-device with Apple Intelligence."
    case .frameworkUnavailable:
      "On-device planning isn't available here."
    }
  }
}

/// Conformed to by planners that can report whether Apple's on-device model is
/// currently backing generation. `PromptPlannerFactory.makeDefaultPlanner()`
/// always returns a conformer in production; `LocalPromptPlanner` on its own
/// does not conform, since it never consults the on-device model at all.
public protocol PlannerAvailabilityReporting: Sendable {
  var plannerAvailability: PlannerAvailability { get }
}
