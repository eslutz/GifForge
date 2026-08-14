import Foundation
import Testing
@testable import GifForgeCore

@Suite("Generation history lifecycle")
struct GenerationHistoryLifecycleTests {
  private func makeContainer() throws -> (root: URL, media: URL) {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "gifforge-history-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let media = root.appending(path: "GeneratedGIFs", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
    return (root, media)
  }

  private func writeGIF(named fileName: String, in media: URL) throws -> URL {
    let url = media.appending(path: fileName)
    try Data("GIF89a".utf8).write(to: url)
    return url
  }

  @Test("Evicting past the item cap deletes the evicted GIF files")
  func evictionDeletesFiles() async throws {
    let (root, media) = try makeContainer()
    let store = GenerationHistoryStore(directoryURL: root)

    var firstURL: URL?
    for index in 0...GenerationHistoryStore.maxItems {
      let url = try writeGIF(named: "GifForge-\(index).gif", in: media)
      if index == 0 {
        firstURL = url
      }
      try await store.save(GenerationHistoryItem(prompt: "p\(index)", captionText: nil, gifURL: url))
    }

    let items = try await store.load()
    #expect(items.count == GenerationHistoryStore.maxItems)
    #expect(FileManager.default.fileExists(atPath: firstURL!.path) == false)
  }

  @Test("Clear deletes referenced and orphaned GIF files")
  func clearDeletesFiles() async throws {
    let (root, media) = try makeContainer()
    let store = GenerationHistoryStore(directoryURL: root)

    let tracked = try writeGIF(named: "GifForge-tracked.gif", in: media)
    let orphan = try writeGIF(named: "GifForge-orphan.gif", in: media)
    let foreign = media.appending(path: "keep-me.txt")
    try Data("not ours".utf8).write(to: foreign)
    try await store.save(GenerationHistoryItem(prompt: "p", captionText: nil, gifURL: tracked))

    try await store.clear()

    #expect(try await store.load().isEmpty)
    #expect(FileManager.default.fileExists(atPath: tracked.path) == false)
    #expect(FileManager.default.fileExists(atPath: orphan.path) == false)
    #expect(FileManager.default.fileExists(atPath: foreign.path))
  }

  @Test("Replacing an item deletes the superseded GIF file")
  func replaceDeletesSupersededFile() async throws {
    let (root, media) = try makeContainer()
    let store = GenerationHistoryStore(directoryURL: root)

    let original = try writeGIF(named: "GifForge-original.gif", in: media)
    let originalItem = GenerationHistoryItem(prompt: "p", captionText: nil, gifURL: original)
    try await store.save(originalItem)

    let recaptioned = try writeGIF(named: "GifForge-recaptioned.gif", in: media)
    let newItem = GenerationHistoryItem(prompt: "p", captionText: "caption", gifURL: recaptioned)
    try await store.save(newItem, replacingItemWithID: originalItem.id)

    let items = try await store.load()
    #expect(items.count == 1)
    #expect(items.first?.captionText == "caption")
    #expect(FileManager.default.fileExists(atPath: original.path) == false)
    #expect(FileManager.default.fileExists(atPath: recaptioned.path))
  }

  @Test("Legacy absolute-path history migrates to file-name storage")
  func legacyHistoryMigrates() async throws {
    let (root, media) = try makeContainer()
    let gif = try writeGIF(named: "GifForge-legacy.gif", in: media)

    // Simulate an entry written by the old schema from a container path that no
    // longer exists after an app update.
    let staleContainerURL = URL(filePath: "/private/var/mobile/Containers/Old/GeneratedGIFs/GifForge-legacy.gif")
    _ = gif
    let legacyItem = GenerationHistoryItem(prompt: "legacy", captionText: nil, gifURL: staleContainerURL)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([legacyItem]).write(to: root.appending(path: "generation-history.json"))

    let store = GenerationHistoryStore(directoryURL: root)
    let items = try await store.load()

    #expect(items.count == 1)
    #expect(items.first?.gifURL.lastPathComponent == "GifForge-legacy.gif")
    #expect(items.first?.gifURL.path.hasPrefix(media.path) == true)
  }
}

@Suite("Composer draft store")
struct ComposerDraftStoreTests {
  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "gifforge-draft-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("Draft with photo round-trips")
  func draftRoundTrips() async throws {
    let store = ComposerDraftStore(directoryURL: try makeDirectory())
    let draft = ComposerDraft(
      prompt: "dancing corgi",
      captionModeRawValue: CaptionMode.userText.rawValue,
      explicitCaption: "friday mood",
      selectedCaption: "",
      pickedMediaMimeType: "image/jpeg"
    )
    let imageData = Data("fake-jpeg".utf8)

    try await store.save(draft, sourceMediaData: imageData)
    let restored = try await store.load()

    #expect(restored?.draft.prompt == "dancing corgi")
    #expect(restored?.draft.captionModeRawValue == "userText")
    #expect(restored?.draft.explicitCaption == "friday mood")
    #expect(restored?.draft.pickedMediaMimeType == "image/jpeg")
    #expect(restored?.sourceMediaData == imageData)
  }

  @Test("Draft with picked video round-trips")
  func draftWithVideoRoundTrips() async throws {
    let store = ComposerDraftStore(directoryURL: try makeDirectory())
    let draft = ComposerDraft(
      prompt: "looping clip",
      captionModeRawValue: CaptionMode.none.rawValue,
      explicitCaption: "",
      selectedCaption: "",
      pickedMediaMimeType: "video/mp4"
    )
    let videoData = Data("fake-mp4".utf8)

    try await store.save(draft, sourceMediaData: videoData)
    let restored = try await store.load()

    #expect(restored?.draft.pickedMediaMimeType == "video/mp4")
    #expect(restored?.sourceMediaData == videoData)
  }

  @Test("Empty draft clears any stored draft")
  func emptyDraftClears() async throws {
    let store = ComposerDraftStore(directoryURL: try makeDirectory())
    try await store.save(
      ComposerDraft(
        prompt: "something",
        captionModeRawValue: CaptionMode.none.rawValue,
        explicitCaption: "",
        selectedCaption: ""
      ),
      sourceMediaData: nil
    )

    try await store.save(
      ComposerDraft(
        prompt: "  ",
        captionModeRawValue: CaptionMode.none.rawValue,
        explicitCaption: "",
        selectedCaption: ""
      ),
      sourceMediaData: nil
    )

    #expect(try await store.load() == nil)
  }

  @Test("Expired drafts are discarded on load")
  func expiredDraftDiscarded() async throws {
    let store = ComposerDraftStore(directoryURL: try makeDirectory())
    let draft = ComposerDraft(
      prompt: "old prompt",
      captionModeRawValue: CaptionMode.none.rawValue,
      explicitCaption: "",
      selectedCaption: "",
      updatedAt: Date().addingTimeInterval(-25 * 60 * 60)
    )

    try await store.save(draft, sourceMediaData: nil)

    #expect(try await store.load() == nil)
  }
}
