import Foundation
import Testing
@testable import GifForgeCore

#if canImport(FoundationModels)
import FoundationModels

// This machine's SDK is iOS/macOS 26.x — well above the FoundationModels 26.0
// availability floor — so these tests construct and classify REAL
// `LanguageModelSession.GenerationError` values rather than fakes. They do not
// invoke the live model (no session.respond calls), so they run deterministically
// in CI/sandboxed environments without Apple Intelligence hardware. The
// `#available` check happens inside each test body (rather than as a decl
// attribute) because this toolchain doesn't allow combining `@available` with
// the `@Test`/`@Suite` macros on the same declaration.
@Suite("FoundationModels error classification")
struct FoundationModelsErrorClassifierTests {
  @Test("Guardrail violation is classified as a rejection")
  func guardrailViolationIsRejection() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    let error = LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "test"))
    #expect(FoundationModelsErrorClassifier.isGuardrailRejection(error))
  }

  @Test("Refusal is classified as a rejection")
  func refusalIsRejection() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
    let error = LanguageModelSession.GenerationError.refusal(refusal, .init(debugDescription: "test"))
    #expect(FoundationModelsErrorClassifier.isGuardrailRejection(error))
  }

  @Test("Every non-safety generation error is NOT classified as a rejection")
  func nonSafetyErrorsAreNotRejections() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
    let nonSafetyErrors: [LanguageModelSession.GenerationError] = [
      .exceededContextWindowSize(context),
      .assetsUnavailable(context),
      .unsupportedGuide(context),
      .unsupportedLanguageOrLocale(context),
      .decodingFailure(context),
      .rateLimited(context),
      .concurrentRequests(context)
    ]

    for error in nonSafetyErrors {
      #expect(!FoundationModelsErrorClassifier.isGuardrailRejection(error))
    }
  }

  @Test("A non-FoundationModels error is not classified as a rejection")
  func unrelatedErrorIsNotRejection() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    #expect(!FoundationModelsErrorClassifier.isGuardrailRejection(GifForgeError.emptyPrompt))
  }

  @Test("Explanation is nil for an unrelated error")
  func explanationIsNilForUnrelatedError() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    #expect(FoundationModelsErrorClassifier.explanation(for: GifForgeError.emptyPrompt) == nil)
  }

  @Test("Explanation is present for a guardrail violation")
  func explanationIsPresentForGuardrailViolation() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    let error = LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "test"))
    #expect(FoundationModelsErrorClassifier.explanation(for: error) != nil)
  }
}

@Suite("FoundationModelsPromptPlanner availability reporting")
struct PlannerAvailabilityReportingTests {
  @Test("Availability mirrors SystemLanguageModel and matches canUseOnDeviceFoundationModels")
  func availabilityMirrorsSystemLanguageModel() throws {
    guard #available(iOS 26.0, macOS 26.0, *) else { return }
    let planner = FoundationModelsPromptPlanner()

    // The two must never disagree: canUseOnDeviceFoundationModels gates which
    // code path a real request takes, and plannerAvailability is what the UI
    // shows the user about that same decision.
    #expect(planner.plannerAvailability.isOnDevice == planner.canUseOnDeviceFoundationModels)
  }
}
#endif

@Suite("Planner availability reason copy")
struct PlannerUnavailableReasonTests {
  @Test(
    "Every reason has non-empty display copy",
    arguments: [
      PlannerUnavailableReason.deviceNotEligible,
      .appleIntelligenceNotEnabled,
      .modelNotReady,
      .osVersionTooOld,
      .frameworkUnavailable
    ]
  )
  func reasonsHaveDisplayCopy(reason: PlannerUnavailableReason) {
    #expect(!reason.displayMessage.isEmpty)
  }

  @Test("LocalPromptPlanner does not conform to PlannerAvailabilityReporting")
  func localPlannerHasNoAvailabilityReporting() {
    let planner: any PromptPlanning = LocalPromptPlanner()
    #expect((planner as? any PlannerAvailabilityReporting) == nil)
  }

  @Test("prewarmIfPossible is a no-op default for planners with nothing to warm")
  func prewarmDefaultIsNoop() {
    // Exercises the protocol extension default; must not throw or crash.
    LocalPromptPlanner().prewarmIfPossible()
  }
}

@Suite("Prompt rejection error copy")
struct PromptRejectedErrorTests {
  @Test("Rejection with an explanation includes it in the user-facing message")
  func rejectionWithExplanation() {
    let error = GifForgeError.promptRejected(explanation: "unsafe content")
    #expect(error.userFacingMessage.contains("unsafe content"))
    #expect(error.userFacingMessage.contains("reword"))
  }

  @Test("Rejection without an explanation still gives actionable copy")
  func rejectionWithoutExplanation() {
    let error = GifForgeError.promptRejected(explanation: nil)
    #expect(error.userFacingMessage.contains("reword"))
  }
}
