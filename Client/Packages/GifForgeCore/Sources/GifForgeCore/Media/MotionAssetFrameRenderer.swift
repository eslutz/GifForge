import Foundation

public struct MotionAssetFrameRenderer: Sendable {
  public var frameSequenceRenderer: FrameSequenceRenderer
  public var mp4FrameExtractor: MP4FrameExtractor

  public init(
    frameSequenceRenderer: FrameSequenceRenderer = FrameSequenceRenderer(),
    mp4FrameExtractor: MP4FrameExtractor = MP4FrameExtractor()
  ) {
    self.frameSequenceRenderer = frameSequenceRenderer
    self.mp4FrameExtractor = mp4FrameExtractor
  }

  public func renderFrames(
    from asset: GeneratedMotionAsset,
    caption: String?,
    onFrame: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
  ) async throws -> [GIFFrame] {
    switch asset {
    case let .frameSequence(frameSequence):
      try frameSequenceRenderer.renderFrames(from: frameSequence, caption: caption)
    case let .mp4(url):
      try await mp4FrameExtractor.extractFrames(from: url, caption: caption, onFrame: onFrame)
    }
  }
}
