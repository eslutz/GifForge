import Foundation

/// Composer input worth restoring after Messages kills the extension process:
/// the prompt, caption choices, and (via a sidecar file) any selected photo,
/// animated GIF, or video. `pickedMediaMimeType` is nil when nothing is
/// selected; otherwise it identifies how to interpret the sidecar blob on
/// restore (for example "image/jpeg" for a picked photo, "image/gif" or
/// "video/mp4"/"video/quicktime" for passthrough source media).
public struct ComposerDraft: Codable, Equatable, Sendable {
  public var prompt: String
  public var captionModeRawValue: String
  public var explicitCaption: String
  public var selectedCaption: String
  public var pickedMediaMimeType: String?
  public var updatedAt: Date

  public init(
    prompt: String,
    captionModeRawValue: String,
    explicitCaption: String,
    selectedCaption: String,
    pickedMediaMimeType: String? = nil,
    updatedAt: Date = Date()
  ) {
    self.prompt = prompt
    self.captionModeRawValue = captionModeRawValue
    self.explicitCaption = explicitCaption
    self.selectedCaption = selectedCaption
    self.pickedMediaMimeType = pickedMediaMimeType
    self.updatedAt = updatedAt
  }

  public var isEmpty: Bool {
    prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && explicitCaption.isEmpty
      && selectedCaption.isEmpty
      && pickedMediaMimeType == nil
  }
}

public actor ComposerDraftStore {
  private let draftURL: URL
  private let sourceMediaURL: URL
  private let expirationInterval: TimeInterval
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    directoryURL: URL,
    expirationInterval: TimeInterval = 24 * 60 * 60
  ) {
    self.draftURL = directoryURL.appending(path: "composer-draft.json")
    self.sourceMediaURL = directoryURL.appending(path: "composer-draft-source-image.dat")
    self.expirationInterval = expirationInterval
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    self.encoder.dateEncodingStrategy = .iso8601
    self.decoder.dateDecodingStrategy = .iso8601
  }

  public func save(_ draft: ComposerDraft, sourceMediaData: Data?) throws {
    guard !draft.isEmpty else {
      try clear()
      return
    }

    do {
      try FileManager.default.createDirectory(
        at: draftURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try encoder.encode(draft).write(to: draftURL, options: .atomic)
      if let sourceMediaData {
        try sourceMediaData.write(to: sourceMediaURL, options: .atomic)
      } else {
        try? FileManager.default.removeItem(at: sourceMediaURL)
      }
    } catch {
      throw GifForgeError.storageFailed(message: error.localizedDescription)
    }
  }

  public func load(now: Date = Date()) throws -> (draft: ComposerDraft, sourceMediaData: Data?)? {
    guard FileManager.default.fileExists(atPath: draftURL.path) else {
      return nil
    }

    do {
      let draft = try decoder.decode(ComposerDraft.self, from: Data(contentsOf: draftURL))
      guard now.timeIntervalSince(draft.updatedAt) <= expirationInterval else {
        try clear()
        return nil
      }

      let mediaData = draft.pickedMediaMimeType != nil ? try? Data(contentsOf: sourceMediaURL) : nil
      return (draft, mediaData)
    } catch {
      throw GifForgeError.storageFailed(message: error.localizedDescription)
    }
  }

  public func clear() throws {
    for url in [draftURL, sourceMediaURL] where FileManager.default.fileExists(atPath: url.path) {
      do {
        try FileManager.default.removeItem(at: url)
      } catch {
        throw GifForgeError.storageFailed(message: error.localizedDescription)
      }
    }
  }
}
