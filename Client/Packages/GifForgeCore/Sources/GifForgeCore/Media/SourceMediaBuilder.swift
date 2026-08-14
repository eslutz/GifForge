import Foundation

/// Builds a `SourceMedia` payload from raw picked bytes (an animated GIF, or an
/// MP4/MOV video) for the video-to-GIF generation path, enforcing the same size
/// budget the backend's moderation policy enforces so an oversized pick fails
/// fast locally instead of after a full upload attempt.
public enum SourceMediaBuilder {
  /// The backend caps `sourceMedia.dataBase64` at 70,000,000 characters
  /// (`Backend/Safety/ModerationPolicy.cs`), which is ~52MB decoded. This stays
  /// comfortably under that after base64's ~33% expansion plus JSON overhead.
  public static let maxDecodedBytes = 45_000_000

  public static func makeSourceMedia(
    data: Data,
    mimeType: String,
    fileName: String? = nil,
    role: String? = nil
  ) throws -> SourceMedia {
    guard data.count <= maxDecodedBytes else {
      throw GifForgeError.sourceMediaTooLarge(byteCount: data.count, limit: maxDecodedBytes)
    }

    return SourceMedia(
      dataBase64: data.base64EncodedString(),
      mimeType: mimeType,
      fileName: fileName,
      role: role
    )
  }
}
