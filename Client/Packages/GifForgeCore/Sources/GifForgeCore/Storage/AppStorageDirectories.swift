import Foundation
import os
#if canImport(Security)
import Security
#endif

public enum AppStorageDirectories {
  public static let appGroupIdentifier = "group.dev.ericslutz.gifforge"
  public static let keychainAccessGroup = "QS3GC3CT43.dev.ericslutz.gifforge.auth"

  private static let logger = Logger(subsystem: "dev.ericslutz.gifforge", category: "SharedStorage")

  public static func sharedContainerURL(fileManager: FileManager = .default) -> URL {
    if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
      return containerURL
    }

    // Falling back means the app and extension write to separate sandboxes and stop
    // sharing history, drafts, and settings. Recoverable in release, loud in development.
    logger.fault("App Group container \(appGroupIdentifier, privacy: .public) is unavailable; falling back to the local Documents directory. App and extension state will not be shared.")
    return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  public static func generatedMediaDirectory(fileManager: FileManager = .default) throws -> URL {
    let url = sharedContainerURL(fileManager: fileManager).appending(path: "GeneratedGIFs", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  #if DEBUG
  /// Called from app and extension startup in DEBUG builds. Crashes early with a clear
  /// message when the App Group container or the keychain access group is misconfigured
  /// (for example after a signing-team change), instead of silently splitting state.
  public static func assertSharedStorageConfigured(fileManager: FileManager = .default) {
    if fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) == nil {
      assertionFailure(
        "App Group container '\(appGroupIdentifier)' is unavailable. Check the App Groups capability on both the app and Messages extension App IDs."
      )
    }

    #if canImport(Security) && !targetEnvironment(simulator)
    // The Simulator ignores keychain access groups, so only probe on hardware.
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "dev.ericslutz.gifforge.shared-storage-probe",
      kSecAttrAccount as String: "probe",
      kSecAttrAccessGroup as String: keychainAccessGroup,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: Data("probe".utf8)
    ]
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "dev.ericslutz.gifforge.shared-storage-probe",
      kSecAttrAccount as String: "probe",
      kSecAttrAccessGroup as String: keychainAccessGroup
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    let status = SecItemAdd(attributes as CFDictionary, nil)
    SecItemDelete(deleteQuery as CFDictionary)
    if status == errSecMissingEntitlement {
      assertionFailure(
        "Keychain access group '\(keychainAccessGroup)' is not grantable. The hardcoded team prefix " +
        "no longer matches this build's AppIdentifierPrefix — update AppStorageDirectories.keychainAccessGroup " +
        "and the keychain-access-groups entitlement together."
      )
    }
    #endif
  }
  #endif
}
