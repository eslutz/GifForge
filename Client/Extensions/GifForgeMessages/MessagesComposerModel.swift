import Foundation
import Messages
import Observation
import GifForgeCore

enum ComposerPhase: Equatable {
  case idle
  case planning
  case submitting
  case generating
  case rendering
  case preview

  var title: String {
    switch self {
    case .idle:
      String(localized: "Ready")
    case .planning:
      String(localized: "Planning")
    case .submitting:
      String(localized: "Submitting")
    case .generating:
      String(localized: "Generating")
    case .rendering:
      String(localized: "Rendering")
    case .preview:
      String(localized: "Preview")
    }
  }
}

/// What the user has picked to animate, if anything. `.image` re-encodes and
/// downsizes through `ImagePreprocessor` as before; `.animatedGIF`/`.video`
/// pass the original bytes through to the backend as `SourceMedia` untouched
/// (the backend's video-to-GIF path already accepted these — the client never
/// had UI to reach it).
enum SelectedMediaKind: Equatable {
  case none
  case image
  case animatedGIF
  case video
}

struct PickedSourceMedia: Equatable {
  var data: Data
  var mimeType: String
  var fileName: String?
  var kind: Kind

  enum Kind: Equatable {
    case animatedGIF
    case video
  }
}

@MainActor
@Observable
final class MessagesComposerModel {
  var prompt = ""
  var captionMode: CaptionMode = .none
  var explicitCaption = ""
  var selectedCaption = ""
  var captionSuggestions: [CaptionSuggestion] = []
  var sourceImageData: Data?
  var selectedSourceMedia: PickedSourceMedia?
  var selectedMediaPreviewURL: URL?
  var previewGIFURL: URL?
  var phase: ComposerPhase = .idle
  var renderProgress: GenerationRenderProgress?
  var errorMessage: String?
  var retryPromptMessage: String?
  var needsContainingAppSetup = false
  var plannerAvailability: PlannerAvailability = .unavailable(.frameworkUnavailable)
  var recentItems: [GenerationHistoryItem] = []
  var presentationStyle: MSMessagesAppPresentationStyle = .compact
  var canApplyCaptionEdit: Bool {
    phase == .preview && lastMotionAsset != nil
  }

  @ObservationIgnored private let planner: any PromptPlanning = PromptPlannerFactory.makeDefaultPlanner()
  @ObservationIgnored private let pipeline = GenerationPipeline()
  @ObservationIgnored private let defaults = UserDefaults(suiteName: AppStorageDirectories.appGroupIdentifier) ?? .standard
  @ObservationIgnored private let activeGenerationStore = ActiveGenerationStore(
    directoryURL: AppStorageDirectories.sharedContainerURL()
  )
  @ObservationIgnored private let historyStore = GenerationHistoryStore(
    directoryURL: AppStorageDirectories.sharedContainerURL()
  )
  @ObservationIgnored private let draftStore = ComposerDraftStore(
    directoryURL: AppStorageDirectories.sharedContainerURL()
  )
  @ObservationIgnored private var lastMotionAsset: GeneratedMotionAsset?
  @ObservationIgnored private var lastPrompt: String?
  @ObservationIgnored private var lastHistoryItemID: UUID?
  @ObservationIgnored private var pendingRetryMaterial: GenerationRetryMaterial?
  @ObservationIgnored private var activeTask: Task<Void, Never>?
  @ObservationIgnored private var preprocessTask: Task<ProcessedSourceImage?, Never>?

  var canGenerate: Bool {
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
  }

  var isWorking: Bool {
    phase == .planning || phase == .submitting || phase == .generating || phase == .rendering
  }

  var hasImage: Bool {
    sourceImageData != nil
  }

  var selectedMediaKind: SelectedMediaKind {
    if sourceImageData != nil {
      return .image
    }

    switch selectedSourceMedia?.kind {
    case .animatedGIF:
      return .animatedGIF
    case .video:
      return .video
    case nil:
      return .none
    }
  }

  var canRetryGeneration: Bool {
    retryPromptMessage != nil && phase == .idle
  }

  func loadRecent() async {
    do {
      recentItems = try await historyStore.load()
    } catch {
      handle(error)
    }
  }

  /// Warms the on-device model ahead of the first real generation, and refreshes
  /// the availability chip so it's accurate as soon as the drawer opens rather
  /// than only after a planning call completes.
  func prepareForForeground() {
    refreshPlannerAvailability()
    planner.prewarmIfPossible()
  }

  private func refreshPlannerAvailability() {
    plannerAvailability = (planner as? any PlannerAvailabilityReporting)?.plannerAvailability
      ?? .unavailable(.frameworkUnavailable)
  }

  func setSourceImageData(_ data: Data?) {
    clearSourceMedia()
    sourceImageData = data
    preprocessTask?.cancel()
    guard let data else {
      preprocessTask = nil
      return
    }

    // Decode and downscale once, in the background, at selection time — not on the
    // main actor at generate time.
    let pipeline = pipeline
    preprocessTask = Task {
      try? await pipeline.preprocessImage(data)
    }
  }

  /// Selects an animated GIF or MP4/MOV video to pass through to the backend's
  /// video-to-GIF path as `SourceMedia`, unmodified (unlike a static photo,
  /// which is downscaled and re-encoded).
  func setSourceMedia(data: Data, mimeType: String, fileName: String?, kind: PickedSourceMedia.Kind) {
    errorMessage = nil
    guard data.count <= SourceMediaBuilder.maxDecodedBytes else {
      handle(GifForgeError.sourceMediaTooLarge(byteCount: data.count, limit: SourceMediaBuilder.maxDecodedBytes))
      return
    }

    sourceImageData = nil
    preprocessTask?.cancel()
    preprocessTask = nil
    clearMediaPreviewFile()

    selectedSourceMedia = PickedSourceMedia(data: data, mimeType: mimeType, fileName: fileName, kind: kind)

    guard kind == .animatedGIF else {
      return
    }

    // Reuse the same ImageIO-animated preview the generated result uses, by
    // writing the picked bytes to a throwaway temp file.
    let url = FileManager.default.temporaryDirectory.appending(path: "GifForge-picked-\(UUID().uuidString).gif")
    if (try? data.write(to: url, options: .atomic)) != nil {
      selectedMediaPreviewURL = url
    }
  }

  func clearSourceMedia() {
    selectedSourceMedia = nil
    clearMediaPreviewFile()
  }

  private func clearMediaPreviewFile() {
    if let url = selectedMediaPreviewURL {
      try? FileManager.default.removeItem(at: url)
    }
    selectedMediaPreviewURL = nil
  }

  func requestCaptionSuggestions() {
    Task {
      do {
        errorMessage = nil
        let request = try await makeStructuredRequest(caption: CaptionRequest(mode: .suggestWithAI))
        captionSuggestions = try await planner.suggestCaptions(for: request)
        selectedCaption = captionSuggestions.first?.text ?? ""
        refreshPlannerAvailability()
      } catch {
        refreshPlannerAvailability()
        handle(error)
      }
    }
  }

  func generate() {
    activeTask?.cancel()
    activeTask = Task {
      await runGeneration()
    }
  }

  func retryGeneration() {
    guard let retryMaterial = pendingRetryMaterial else {
      retryPromptMessage = nil
      return
    }

    activeTask?.cancel()
    activeTask = Task {
      await runRetry(retryMaterial: retryMaterial)
    }
  }

  func dismissRetryPrompt() {
    retryPromptMessage = nil
  }

  func cancelPendingRetry() {
    pendingRetryMaterial = nil
    retryPromptMessage = nil
    Task {
      try? await activeGenerationStore.clear()
    }
  }

  func applyCaptionEdit() {
    Task {
      do {
        guard let lastMotionAsset else {
          return
        }

        errorMessage = nil
        let captionText = try captionTextForCurrentMode()
        try await renderPreview(
          from: lastMotionAsset,
          prompt: lastPrompt ?? prompt,
          captionText: captionText
        )
      } catch {
        phase = .preview
        handle(error)
      }
    }
  }

  func resumeActiveJobIfNeeded() async {
    guard !isWorking else {
      return
    }

    do {
      guard let snapshot = try await activeGenerationStore.load(), previewGIFURL == nil else {
        return
      }

      try await finish(
        job: snapshot.job,
        prompt: snapshot.prompt,
        captionText: snapshot.captionText,
        retryMaterial: snapshot.retryMaterial,
        client: backendClient()
      )
    } catch is CancellationError {
      resetAfterCancellation()
    } catch {
      handle(error)
    }
  }

  /// Called when the Messages drawer closes: stop in-flight work (the saved job
  /// snapshot resumes it on the next open) and keep the user's typed input.
  func handleWillResignActive() {
    activeTask?.cancel()
    activeTask = nil
    if isWorking {
      resetAfterCancellation()
    }
    persistDraft()
  }

  func restoreDraftIfNeeded() async {
    guard phase == .idle, previewGIFURL == nil, prompt.isEmpty, selectedMediaKind == .none else {
      return
    }

    guard let restored = try? await draftStore.load() else {
      return
    }

    prompt = restored.draft.prompt
    captionMode = CaptionMode(rawValue: restored.draft.captionModeRawValue) ?? .none
    explicitCaption = restored.draft.explicitCaption
    selectedCaption = restored.draft.selectedCaption

    guard let mediaData = restored.sourceMediaData, let mimeType = restored.draft.pickedMediaMimeType else {
      return
    }

    switch mimeType {
    case "image/gif":
      setSourceMedia(data: mediaData, mimeType: mimeType, fileName: nil, kind: .animatedGIF)
    case "video/mp4", "video/quicktime":
      setSourceMedia(data: mediaData, mimeType: mimeType, fileName: nil, kind: .video)
    case Self.staticImageDraftSentinel:
      setSourceImageData(mediaData)
    default:
      break
    }
  }

  func clearDraftAfterInsert() {
    let draftStore = draftStore
    Task {
      try? await draftStore.clear()
    }
  }

  /// Sentinel `pickedMediaMimeType` meaning "restore as a static photo via
  /// setSourceImageData" — not a literal claim about the raw picked bytes'
  /// format, which ImageIO auto-detects regardless (HEIC/PNG/JPEG all work).
  private static let staticImageDraftSentinel = "application/x-gifforge-picked-photo"

  private func persistDraft() {
    let mediaData: Data?
    let mimeType: String?
    if let sourceImageData {
      mediaData = sourceImageData
      mimeType = Self.staticImageDraftSentinel
    } else if let selectedSourceMedia {
      mediaData = selectedSourceMedia.data
      mimeType = selectedSourceMedia.mimeType
    } else {
      mediaData = nil
      mimeType = nil
    }

    let draft = ComposerDraft(
      prompt: prompt,
      captionModeRawValue: captionMode.rawValue,
      explicitCaption: explicitCaption,
      selectedCaption: selectedCaption,
      pickedMediaMimeType: mimeType
    )
    let draftStore = draftStore
    Task {
      try? await draftStore.save(draft, sourceMediaData: mediaData)
    }
  }

  private func runGeneration() async {
    do {
      errorMessage = nil
      retryPromptMessage = nil
      needsContainingAppSetup = false
      pendingRetryMaterial = nil
      previewGIFURL = nil
      lastMotionAsset = nil
      lastPrompt = nil
      lastHistoryItemID = nil
      phase = .planning

      var structuredRequest = try await makeStructuredRequest(caption: captionRequestForGeneration())
      refreshPlannerAvailability()
      if captionMode == .suggestWithAI && structuredRequest.caption.text?.isEmpty != false {
        captionSuggestions = try await planner.suggestCaptions(for: structuredRequest)
        selectedCaption = selectedCaption.isEmpty ? captionSuggestions.first?.text ?? "" : selectedCaption
        structuredRequest.caption = CaptionRequest(mode: .suggestWithAI, text: selectedCaption)
      }

      phase = .submitting
      let client = backendClient()
      let retryMaterial = GenerationRetryMaterial(request: structuredRequest)
      let job = try await client.createJob(structuredRequest)
      try await activeGenerationStore.save(ActiveGenerationSnapshot(
        job: job,
        prompt: structuredRequest.cleanedPrompt,
        captionText: structuredRequest.caption.text,
        retryMaterial: retryMaterial
      ))

      try await finish(
        job: job,
        prompt: structuredRequest.cleanedPrompt,
        captionText: structuredRequest.caption.text,
        retryMaterial: retryMaterial,
        client: client
      )
    } catch is CancellationError {
      resetAfterCancellation()
    } catch {
      refreshPlannerAvailability()
      phase = .idle
      handle(error)
    }
  }

  private func runRetry(retryMaterial: GenerationRetryMaterial) async {
    do {
      errorMessage = nil
      retryPromptMessage = nil
      pendingRetryMaterial = nil
      phase = .submitting

      let client = backendClient()
      let job = try await client.createJob(retryMaterial.request)
      try await activeGenerationStore.save(ActiveGenerationSnapshot(
        job: job,
        prompt: retryMaterial.request.cleanedPrompt,
        captionText: retryMaterial.request.caption.text,
        retryMaterial: retryMaterial
      ))

      try await finish(
        job: job,
        prompt: retryMaterial.request.cleanedPrompt,
        captionText: retryMaterial.request.caption.text,
        retryMaterial: retryMaterial,
        client: client
      )
    } catch is CancellationError {
      resetAfterCancellation()
    } catch {
      phase = .idle
      handle(error)
    }
  }

  private func finish(
    job: GenerationJob,
    prompt: String,
    captionText: String?,
    retryMaterial: GenerationRetryMaterial?,
    client: GifForgeBackendClient
  ) async throws {
    phase = .generating
    let completed: GenerationJob
    do {
      completed = try await JobPollingService(client: client).waitForCompletion(startingWith: job)
    } catch let GifForgeError.retryAvailable(failedJob, message) {
      try await prepareClientRetry(
        failedJob: failedJob,
        message: message,
        prompt: prompt,
        captionText: captionText,
        retryMaterial: retryMaterial
      )
      return
    }

    guard let downloadURL = completed.downloadURL else {
      throw GifForgeError.jobFailed(message: "Backend completed without a result URL.")
    }

    let asset = try await client.downloadMotionAsset(from: downloadURL)
    lastMotionAsset = asset
    lastPrompt = prompt

    try await renderPreview(from: asset, prompt: prompt, captionText: captionText)
    try await activeGenerationStore.clear()
  }

  private func prepareClientRetry(
    failedJob: GenerationJob,
    message: String,
    prompt: String,
    captionText: String?,
    retryMaterial: GenerationRetryMaterial?
  ) async throws {
    guard let retryMaterial else {
      throw GifForgeError.jobFailed(message: message)
    }

    var retryRequest = retryMaterial.request
    retryRequest.retryOfJobId = failedJob.retryOfJobId ?? failedJob.id
    let updatedMaterial = GenerationRetryMaterial(request: retryRequest)
    pendingRetryMaterial = updatedMaterial
    retryPromptMessage = message
    phase = .idle

    try await activeGenerationStore.save(ActiveGenerationSnapshot(
      job: failedJob,
      prompt: prompt,
      captionText: captionText,
      retryMaterial: updatedMaterial
    ))
  }

  private func renderPreview(
    from asset: GeneratedMotionAsset,
    prompt: String,
    captionText: String?
  ) async throws {
    phase = .rendering
    renderProgress = nil
    let outputDirectory = try AppStorageDirectories.generatedMediaDirectory()
    let outputURL = try await pipeline.renderGIF(
      from: asset,
      captionText: captionText,
      outputDirectory: outputDirectory
    ) { [weak self] progress in
      Task { @MainActor in
        self?.renderProgress = progress
      }
    }

    renderProgress = nil
    previewGIFURL = outputURL
    phase = .preview

    let item = GenerationHistoryItem(prompt: prompt, captionText: captionText, gifURL: outputURL)
    try await historyStore.save(item, replacingItemWithID: lastHistoryItemID)
    lastHistoryItemID = item.id
    await loadRecent()
  }

  private func makeStructuredRequest(caption: CaptionRequest) async throws -> StructuredGenerationRequest {
    let sourceImage = try await processedSourceImage()
    let sourceMedia = try selectedSourceMedia.map {
      try SourceMediaBuilder.makeSourceMedia(data: $0.data, mimeType: $0.mimeType, fileName: $0.fileName)
    }
    let intent = GenerationIntent(prompt: prompt, sourceMedia: sourceMedia, sourceImage: sourceImage, caption: caption)
    return try await planner.makeStructuredRequest(from: intent)
  }

  private func processedSourceImage() async throws -> ProcessedSourceImage? {
    guard let data = sourceImageData else {
      return nil
    }

    if let preprocessTask, let cached = await preprocessTask.value {
      return cached
    }

    return try await pipeline.preprocessImage(data)
  }

  private func captionRequestForGeneration() throws -> CaptionRequest {
    switch captionMode {
    case .none:
      CaptionRequest(mode: .none)
    case .userText:
      CaptionRequest(mode: .userText, text: explicitCaption)
    case .suggestWithAI:
      CaptionRequest(mode: .suggestWithAI, text: selectedCaption)
    }
  }

  private func captionTextForCurrentMode() throws -> String? {
    switch captionMode {
    case .none:
      nil
    case .userText:
      try CaptionValidator.normalizedExplicitCaption(explicitCaption)
    case .suggestWithAI:
      try CaptionValidator.normalizedExplicitCaption(selectedCaption)
    }
  }

  private func resetAfterCancellation() {
    if phase != .preview {
      phase = .idle
    }
    renderProgress = nil
  }

  private func handle(_ error: Error) {
    if error is CancellationError {
      resetAfterCancellation()
      return
    }

    if case GifForgeError.accountSessionMissing = error {
      needsContainingAppSetup = true
    }

    if case let GifForgeError.backendRejected(statusCode, _) = error,
       statusCode == 401 || statusCode == 403,
       ((try? KeychainBackendAuthTokenStore().load()) ?? nil) == nil {
      // Rejected and no stored session at all: the fix is opening the containing app.
      needsContainingAppSetup = true
    }

    errorMessage = error.gifforgeUserFacingMessage
  }

  private func backendClient() -> GifForgeBackendClient {
    let rawValue = defaults.string(forKey: "backendBaseURL") ?? "http://127.0.0.1:8787"
    let baseURL = URL(string: rawValue) ?? URL(string: "http://127.0.0.1:8787")!
    let tokenAuthorizer = RefreshingBearerTokenAuthorizer(baseURL: baseURL)

    guard defaults.bool(forKey: "backendRequiresAppAttest") else {
      return GifForgeBackendClient(baseURL: baseURL, authorizer: tokenAuthorizer)
    }

    let provider = SharedAppAttestSessionProvider(
      store: SharedAppAttestSessionStore(defaults: defaults)
    )
    return GifForgeBackendClient(
      baseURL: baseURL,
      authorizer: CompositeBackendRequestAuthorizer(authorizers: [
        tokenAuthorizer,
        AppAttestSessionAuthorizer(provider: provider)
      ])
    )
  }
}
