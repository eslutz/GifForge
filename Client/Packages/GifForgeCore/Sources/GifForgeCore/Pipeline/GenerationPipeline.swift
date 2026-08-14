import Foundation

/// Granular progress for the client-side half of a generation, suitable for a
/// determinate progress indicator during frame extraction.
public enum GenerationRenderProgress: Equatable, Sendable {
  case rendering(frame: Int, of: Int)
  case encoding
}

/// Runs the CPU-heavy client pipeline stages (photo preprocessing, frame
/// rendering, GIF encoding, file writes) off the main actor. The Messages
/// extension previously did all of this synchronously on the UI thread.
public actor GenerationPipeline {
  private let imagePreprocessor: ImagePreprocessor
  private let frameRenderer: MotionAssetFrameRenderer
  private let gifRenderer: GIFRenderer

  public init(
    imagePreprocessor: ImagePreprocessor = ImagePreprocessor(),
    frameRenderer: MotionAssetFrameRenderer = MotionAssetFrameRenderer(),
    gifRenderer: GIFRenderer = GIFRenderer()
  ) {
    self.imagePreprocessor = imagePreprocessor
    self.frameRenderer = frameRenderer
    self.gifRenderer = gifRenderer
  }

  public func preprocessImage(_ data: Data) throws -> ProcessedSourceImage {
    try Task.checkCancellation()
    return try imagePreprocessor.processImageData(data)
  }

  /// Renders a motion asset into an encoded GIF in `outputDirectory` and returns the
  /// file URL. Respects task cancellation between and within stages, and steps down
  /// the encode ladder instead of failing when the first encode exceeds 4MB.
  public func renderGIF(
    from asset: GeneratedMotionAsset,
    captionText: String?,
    outputDirectory: URL,
    onProgress: (@Sendable (GenerationRenderProgress) -> Void)? = nil
  ) async throws -> URL {
    try Task.checkCancellation()
    let frames = try await frameRenderer.renderFrames(from: asset, caption: captionText) { completed, total in
      onProgress?(.rendering(frame: completed, of: total))
    }

    try Task.checkCancellation()
    onProgress?(.encoding)
    let outputURL = outputDirectory.appending(path: "GifForge-\(UUID().uuidString).gif")
    try gifRenderer.render(frames: frames, to: outputURL, optionsLadder: GIFRenderOptions.messagesLadder)
    return outputURL
  }
}
