import Foundation
import GifForgeCore

@MainActor
let gifforgeDefaults = UserDefaults(suiteName: AppStorageDirectories.appGroupIdentifier) ?? .standard
