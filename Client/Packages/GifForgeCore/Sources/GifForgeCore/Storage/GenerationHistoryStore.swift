import Foundation

public actor GenerationHistoryStore {
  public static let maxItems = 30

  private let fileURL: URL
  private let mediaDirectoryURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  /// Persisted schema: GIFs are stored by file name and resolved against the media
  /// directory at load time, because absolute app-group container paths change across
  /// app updates and container migrations.
  private struct StoredItem: Codable {
    var id: UUID
    var prompt: String
    var captionText: String?
    var gifFileName: String
    var createdAt: Date
  }

  public init(directoryURL: URL) {
    self.fileURL = directoryURL.appending(path: "generation-history.json")
    self.mediaDirectoryURL = directoryURL.appending(path: "GeneratedGIFs", directoryHint: .isDirectory)
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder.dateEncodingStrategy = .iso8601
    self.decoder.dateDecodingStrategy = .iso8601
  }

  public func load() throws -> [GenerationHistoryItem] {
    try loadStored().map(resolvedItem)
  }

  public func save(_ item: GenerationHistoryItem) throws {
    try save(item, replacingItemWithID: nil)
  }

  /// Saves `item`, optionally replacing an existing entry (caption re-renders replace
  /// their history entry in place instead of accumulating near-duplicates). Files of
  /// replaced or evicted entries are deleted from the shared container.
  public func save(_ item: GenerationHistoryItem, replacingItemWithID replacedID: UUID?) throws {
    var items = try loadStored()
    let newItem = StoredItem(
      id: item.id,
      prompt: item.prompt,
      captionText: item.captionText,
      gifFileName: item.gifURL.lastPathComponent,
      createdAt: item.createdAt
    )

    var removedFileNames: [String] = []
    for staleID in [replacedID, item.id].compactMap({ $0 }) {
      if let index = items.firstIndex(where: { $0.id == staleID }) {
        let stale = items.remove(at: index)
        if stale.gifFileName != newItem.gifFileName {
          removedFileNames.append(stale.gifFileName)
        }
      }
    }

    items.insert(newItem, at: 0)
    if items.count > Self.maxItems {
      removedFileNames.append(contentsOf: items[Self.maxItems...].map(\.gifFileName))
      items = Array(items.prefix(Self.maxItems))
    }

    try write(items)
    deleteMediaFiles(named: removedFileNames)
  }

  public func clear() throws {
    let items = try loadStored()
    try write([])
    deleteMediaFiles(named: items.map(\.gifFileName))
    deleteOrphanedMediaFiles(keeping: [])
  }

  private func loadStored() throws -> [StoredItem] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }

    do {
      let data = try Data(contentsOf: fileURL)
      if let items = try? decoder.decode([StoredItem].self, from: data) {
        return items
      }

      // Legacy schema persisted absolute gifURL values; migrate to file names.
      let legacy = try decoder.decode([GenerationHistoryItem].self, from: data)
      let migrated = legacy.map { item in
        StoredItem(
          id: item.id,
          prompt: item.prompt,
          captionText: item.captionText,
          gifFileName: item.gifURL.lastPathComponent,
          createdAt: item.createdAt
        )
      }
      try write(migrated)
      return migrated
    } catch {
      throw GifForgeError.storageFailed(message: error.localizedDescription)
    }
  }

  private func resolvedItem(_ stored: StoredItem) -> GenerationHistoryItem {
    GenerationHistoryItem(
      id: stored.id,
      prompt: stored.prompt,
      captionText: stored.captionText,
      gifURL: mediaDirectoryURL.appending(path: stored.gifFileName),
      createdAt: stored.createdAt
    )
  }

  private func write(_ items: [StoredItem]) throws {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try encoder.encode(items)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      throw GifForgeError.storageFailed(message: error.localizedDescription)
    }
  }

  private func deleteMediaFiles(named fileNames: [String]) {
    for fileName in fileNames where isManagedMediaFileName(fileName) {
      try? FileManager.default.removeItem(at: mediaDirectoryURL.appending(path: fileName))
    }
  }

  /// Removes generated GIFs that no history entry references, cleaning up files leaked
  /// by earlier versions that never deleted anything.
  private func deleteOrphanedMediaFiles(keeping referencedFileNames: Set<String>) {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mediaDirectoryURL.path) else {
      return
    }

    for fileName in contents
    where isManagedMediaFileName(fileName) && !referencedFileNames.contains(fileName) {
      try? FileManager.default.removeItem(at: mediaDirectoryURL.appending(path: fileName))
    }
  }

  /// Only files GifForge itself wrote are ever deleted.
  private func isManagedMediaFileName(_ fileName: String) -> Bool {
    fileName.hasPrefix("GifForge-") && fileName.hasSuffix(".gif") && !fileName.contains("/")
  }
}
