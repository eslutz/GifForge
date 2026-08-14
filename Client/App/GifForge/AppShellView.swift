import GifForgeCore
import SwiftUI

struct AppShellView: View {
  @State private var history: [GenerationHistoryItem] = []
  @State private var errorMessage: String?

  @AppStorage("hasCompletedOnboarding", store: gifforgeDefaults)
  private var hasCompletedOnboarding = false

  private let historyStore = GenerationHistoryStore(
    directoryURL: AppStorageDirectories.sharedContainerURL()
  )
  private let activeGenerationStore = ActiveGenerationStore(
    directoryURL: AppStorageDirectories.sharedContainerURL()
  )

  var body: some View {
    TabView {
      Tab(String(localized: "GifForge"), systemImage: "sparkles") {
        NavigationStack {
          OverviewView()
        }
      }

      Tab(String(localized: "History"), systemImage: "clock") {
        NavigationStack {
          HistoryView(history: history, clearHistory: clearHistory)
            .task {
              await loadHistory()
            }
        }
      }

      Tab(String(localized: "Settings"), systemImage: "gearshape") {
        NavigationStack {
          SettingsView()
        }
      }
    }
    .alert(String(localized: "GifForge"), isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
    .fullScreenCover(isPresented: Binding(
      get: { shouldShowOnboarding },
      set: { isPresented in
        if !isPresented {
          hasCompletedOnboarding = true
        }
      }
    )) {
      OnboardingView {
        hasCompletedOnboarding = true
      }
    }
  }

  /// Onboarding gates every other UI test on a fresh simulator (no persisted
  /// `hasCompletedOnboarding`), so tests that aren't specifically exercising it
  /// opt out via launch environment — mirrors the `GIFFORGE_UI_TEST_SEED_HISTORY`
  /// pattern below. Never affects a real user launch.
  private var shouldShowOnboarding: Bool {
    #if DEBUG
    if ProcessInfo.processInfo.environment["GIFFORGE_UI_TEST_SKIP_ONBOARDING"] == "1" {
      return false
    }
    #endif
    return !hasCompletedOnboarding
  }

  private func loadHistory() async {
    do {
      #if DEBUG
      try await seedHistoryForUITestsIfNeeded()
      #endif
      history = try await historyStore.load()
    } catch {
      errorMessage = error.gifforgeUserFacingMessage
    }
  }

  private func clearHistory() {
    Task {
      do {
        try await historyStore.clear()
        try await activeGenerationStore.clear()
        history = []
      } catch {
        errorMessage = error.gifforgeUserFacingMessage
      }
    }
  }

  #if DEBUG
  private func seedHistoryForUITestsIfNeeded() async throws {
    guard ProcessInfo.processInfo.environment["GIFFORGE_UI_TEST_SEED_HISTORY"] == "1" else {
      return
    }

    let existingHistory = try await historyStore.load()
    guard existingHistory.isEmpty else {
      return
    }

    let mediaDirectory = try AppStorageDirectories.generatedMediaDirectory()
    let gifURL = mediaDirectory.appending(path: "ui-test-history.gif")
    if !FileManager.default.fileExists(atPath: gifURL.path) {
      try Data("GIF89a".utf8).write(to: gifURL, options: .atomic)
    }

    try await historyStore.save(
      GenerationHistoryItem(
        prompt: "UI test prompt",
        captionText: "UI test caption",
        gifURL: gifURL
      )
    )
  }
  #endif
}
