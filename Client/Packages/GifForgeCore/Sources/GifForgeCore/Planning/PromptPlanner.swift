import Foundation

public protocol PromptPlanning: Sendable {
  func makeStructuredRequest(from intent: GenerationIntent) async throws -> StructuredGenerationRequest
  func suggestCaptions(for request: StructuredGenerationRequest) async throws -> [CaptionSuggestion]

  /// Best-effort hint that a planning call is likely soon, so an on-device model
  /// backing this planner can start preparing its resources early. Never throws
  /// and has no observable effect for planners with nothing to warm.
  func prewarmIfPossible()
}

public extension PromptPlanning {
  func prewarmIfPossible() {}
}

public struct PromptPlannerFactory {
  public static func makeDefaultPlanner() -> any PromptPlanning {
    FoundationModelsPromptPlanner(fallback: LocalPromptPlanner())
  }

  /// Cheap, side-effect-free availability check for UI that wants to show
  /// on-device planning status without needing a full composer session (for
  /// example onboarding). Reads `SystemLanguageModel.default.availability`
  /// only — never creates a session or invokes the model.
  public static func currentAvailability() -> PlannerAvailability {
    FoundationModelsPromptPlanner().plannerAvailability
  }
}
