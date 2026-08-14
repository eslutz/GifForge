import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable
@available(iOS 26.0, macOS 26.0, *)
private struct FoundationGenerationPlan {
  @Guide(description: "A concise cleaned-up GIF prompt with no line breaks.")
  var cleanedPrompt: String

  @Guide(description: "A vivid expanded motion prompt for an AI video provider. Do not ask the provider to render readable text.")
  var expandedPrompt: String

  @Guide(description: "A short negative prompt that prevents readable text, captions, logos, watermarks, and unsafe details.")
  var negativePrompt: String
}

@Generable
@available(iOS 26.0, macOS 26.0, *)
private struct FoundationCaptionPlan {
  @Guide(description: "A short caption under 64 characters.")
  var first: String

  @Guide(description: "A second short caption under 64 characters.")
  var second: String

  @Guide(description: "A third short caption under 64 characters.")
  var third: String
}

/// Classifies FoundationModels errors without touching a live model, so this
/// logic is unit-testable by constructing real `LanguageModelSession.GenerationError`
/// values directly (their cases and `Context`/`Refusal` payloads are public and
/// constructible).
@available(iOS 26.0, macOS 26.0, *)
enum FoundationModelsErrorClassifier {
  /// A guardrail rejection must never be silently routed around by falling back
  /// to the deterministic planner — the user needs to actually change the
  /// prompt, not receive templated content instead without knowing why.
  static func isGuardrailRejection(_ error: Error) -> Bool {
    guard let generationError = error as? LanguageModelSession.GenerationError else {
      return false
    }

    switch generationError {
    case .guardrailViolation, .refusal:
      return true
    default:
      return false
    }
  }

  static func explanation(for error: Error) -> String? {
    guard let generationError = error as? LanguageModelSession.GenerationError else {
      return nil
    }

    return generationError.errorDescription
  }
}
#endif

public struct FoundationModelsPromptPlanner: PromptPlanning {
  private let fallback: any PromptPlanning

  public init(fallback: any PromptPlanning = LocalPromptPlanner()) {
    self.fallback = fallback
  }

  public var canUseOnDeviceFoundationModels: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      return SystemLanguageModel.default.isAvailable
    }

    return false
    #else
    false
    #endif
  }

  public func makeStructuredRequest(from intent: GenerationIntent) async throws -> StructuredGenerationRequest {
    #if canImport(FoundationModels)
    guard #available(iOS 26.0, macOS 26.0, *), canUseOnDeviceFoundationModels else {
      return try await fallback.makeStructuredRequest(from: intent)
    }

    return try await makeFoundationStructuredRequest(from: intent)
    #else
    return try await fallback.makeStructuredRequest(from: intent)
    #endif
  }

  public func suggestCaptions(for request: StructuredGenerationRequest) async throws -> [CaptionSuggestion] {
    #if canImport(FoundationModels)
    guard #available(iOS 26.0, macOS 26.0, *), canUseOnDeviceFoundationModels else {
      return try await fallback.suggestCaptions(for: request)
    }

    return try await makeFoundationCaptionSuggestions(for: request)
    #else
    return try await fallback.suggestCaptions(for: request)
    #endif
  }

  public func prewarmIfPossible() {
    #if canImport(FoundationModels)
    guard #available(iOS 26.0, macOS 26.0, *), canUseOnDeviceFoundationModels else {
      return
    }

    // The underlying model resources are managed centrally by the OS and shared
    // across Apple Intelligence features, so warming a throwaway session here
    // still benefits the real session created for the next actual request.
    LanguageModelSession().prewarm()
    #endif
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private func makeFoundationStructuredRequest(from intent: GenerationIntent) async throws -> StructuredGenerationRequest {
    do {
      let session = LanguageModelSession()
      let mode = generationMode(for: intent)
      let response = try await session.respond(
        to: generationPrompt(for: intent, mode: mode),
        generating: FoundationGenerationPlan.self
      )
      let plan = response.content
      let caption = try normalizeCaption(intent.caption)
      let sourceImageContext = intent.sourceImage.map(SourceImageContext.init(sourceImage:))
      let cleaned = clean(plan.cleanedPrompt)
      guard !cleaned.isEmpty else {
        return try await fallback.makeStructuredRequest(from: intent)
      }

      return StructuredGenerationRequest(
        mode: mode,
        originalPrompt: intent.prompt,
        cleanedPrompt: cleaned,
        expandedPrompt: clean(plan.expandedPrompt),
        negativePrompt: clean(plan.negativePrompt),
        caption: caption,
        sourceMedia: intent.sourceMedia,
        sourceImage: intent.sourceImage,
        sourceImageContext: sourceImageContext,
        options: intent.options
      )
    } catch {
      if FoundationModelsErrorClassifier.isGuardrailRejection(error) {
        throw GifForgeError.promptRejected(explanation: FoundationModelsErrorClassifier.explanation(for: error))
      }

      return try await fallback.makeStructuredRequest(from: intent)
    }
  }

  @available(iOS 26.0, macOS 26.0, *)
  private func makeFoundationCaptionSuggestions(for request: StructuredGenerationRequest) async throws -> [CaptionSuggestion] {
    do {
      let session = LanguageModelSession()
      let response = try await session.respond(
        to: """
        Suggest three brief, punchy captions for this generated GIF.
        Keep every caption under \(CaptionValidator.maxCharacters) characters.
        Prompt: \(request.cleanedPrompt)
        Do not include hashtags, emojis, profanity, or quoted dialogue.
        """,
        generating: FoundationCaptionPlan.self
      )

      let plan = response.content
      let candidates = [plan.first, plan.second, plan.third]
        .map { clean($0) }
        .filter { !$0.isEmpty }
        .map { String($0.prefix(CaptionValidator.maxCharacters)) }

      if candidates.isEmpty {
        return try await fallback.suggestCaptions(for: request)
      }

      return candidates.map { CaptionSuggestion(text: $0) }
    } catch {
      if FoundationModelsErrorClassifier.isGuardrailRejection(error) {
        throw GifForgeError.promptRejected(explanation: FoundationModelsErrorClassifier.explanation(for: error))
      }

      return try await fallback.suggestCaptions(for: request)
    }
  }
  #endif

  private func clean(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\n", with: " ")
      .split(separator: " ")
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func normalizeCaption(_ caption: CaptionRequest) throws -> CaptionRequest {
    switch caption.mode {
    case .none:
      CaptionRequest(mode: .none)
    case .userText:
      CaptionRequest(mode: .userText, text: try CaptionValidator.normalizedExplicitCaption(caption.text ?? ""))
    case .suggestWithAI:
      CaptionRequest(mode: .suggestWithAI, text: caption.text)
    }
  }

  private func generationPrompt(for intent: GenerationIntent, mode: GenerationMode) -> String {
    let sourceImageSummary = intent.sourceImage.map { SourceImageContext(sourceImage: $0).summary } ?? ""
    let source: String
    switch mode {
    case .imageToGIF:
      source = "The user selected a static source image. Plan how to animate that image. \(sourceImageSummary)"
    case .videoToGIF:
      source = "The user selected a GIF, video, MOV, or Live Photo paired MOV. Plan a silent video-to-video transformation."
    case .textToGIF:
      source = "The user wants a text-to-GIF animation."
    }

    return """
    \(source)
    Convert the user's messy request into a provider-ready animation plan.
    Preserve the user's intent. Keep visible readable text out of the provider prompt because captions are rendered locally by the app.
    Original prompt: \(intent.prompt)
    Style preset: \(intent.options.stylePreset)
    Motion intensity: \(intent.options.motionIntensity.rawValue)
    Loop duration: \(String(format: "%.1f", intent.options.loopSeconds)) seconds
    """
  }

  private func generationMode(for intent: GenerationIntent) -> GenerationMode {
    if let sourceMedia = intent.sourceMedia {
      let mimeType = sourceMedia.mimeType.lowercased()
      let role = sourceMedia.role?.lowercased()
      if mimeType == "image/gif" ||
          mimeType.hasPrefix("video/") ||
          role == "video" ||
          role == "livephotopairedvideo" ||
          role == "live-photo-paired-video" {
        return .videoToGIF
      }

      return .imageToGIF
    }

    return intent.sourceImage == nil ? .textToGIF : .imageToGIF
  }
}

extension FoundationModelsPromptPlanner: PlannerAvailabilityReporting {
  public var plannerAvailability: PlannerAvailability {
    #if canImport(FoundationModels)
    guard #available(iOS 26.0, macOS 26.0, *) else {
      return .unavailable(.osVersionTooOld)
    }

    switch SystemLanguageModel.default.availability {
    case .available:
      return .onDevice
    case let .unavailable(reason):
      return .unavailable(Self.mapUnavailableReason(reason))
    }
    #else
    return .unavailable(.frameworkUnavailable)
    #endif
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private static func mapUnavailableReason(
    _ reason: SystemLanguageModel.Availability.UnavailableReason
  ) -> PlannerUnavailableReason {
    switch reason {
    case .deviceNotEligible:
      .deviceNotEligible
    case .appleIntelligenceNotEnabled:
      .appleIntelligenceNotEnabled
    case .modelNotReady:
      .modelNotReady
    @unknown default:
      .modelNotReady
    }
  }
  #endif
}
