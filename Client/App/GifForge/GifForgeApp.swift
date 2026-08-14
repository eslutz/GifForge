import GifForgeCore
import SwiftUI

@main
struct GifForgeApp: App {
  init() {
    #if DEBUG
    AppStorageDirectories.assertSharedStorageConfigured()
    // Lets the onboarding-walkthrough UI test force a first-launch state
    // regardless of what a previous test run persisted to the shared
    // UserDefaults suite, so it isn't order-dependent on other UI tests.
    if ProcessInfo.processInfo.environment["GIFFORGE_UI_TEST_RESET_ONBOARDING"] == "1" {
      gifforgeDefaults.removeObject(forKey: "hasCompletedOnboarding")
    }
    #endif
  }

  var body: some Scene {
    WindowGroup {
      AppShellView()
    }
  }
}
