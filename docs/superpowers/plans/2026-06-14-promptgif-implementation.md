# PromptGIF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build PromptGIF into an App Store-ready iOS 26.5+ iMessage GIF generation app.

**Architecture:** The Messages extension owns the primary user flow while the containing app owns onboarding, settings, and local history. Shared Swift package code owns models, planning, networking, media rendering, and storage. The backend owns validation, moderation, provider abstraction, credentials, job state, and temporary result URLs.

**Tech Stack:** SwiftUI, Messages framework, PhotosUI, ImageIO, CoreGraphics, Apple Foundation Models, XcodeGen, Swift Package Manager, Node 24 backend, provider adapters.

---

### Task 1: Confirm iOS 26.5 SDK Build

**Files:**
- Modify: `project.yml`
- Modify: `Packages/PromptGIFCore/Package.swift`

- [ ] Install Xcode 26.5 or later.
- [ ] Run `xcodegen generate`.
- [ ] Run `xcodebuild -project PromptGIF.xcodeproj -scheme PromptGIF -destination 'generic/platform=iOS Simulator' build`.
- [ ] If deployment target or SDK names changed, update both `project.yml` and `Package.swift`.

### Task 2: Wire Real Foundation Models Planning

**Files:**
- Modify: `Packages/PromptGIFCore/Sources/PromptGIFCore/Planning/FoundationModelsPromptPlanner.swift`
- Add tests under: `Packages/PromptGIFCore/Tests/PromptGIFCoreTests`

- [ ] Replace fallback-only planning with guided local generation using Apple Foundation Models.
- [ ] Keep deterministic fallback for unavailable models.
- [ ] Add tests for empty prompt, structured output, caption suggestions, and unavailable-model fallback.
- [ ] Confirm caption suggestions are user-reviewable and editable.

### Task 3: Persist Active Jobs

**Files:**
- Modify: `Extensions/PromptGIFMessages/MessagesComposerModel.swift`
- Add: `Packages/PromptGIFCore/Sources/PromptGIFCore/Storage/ActiveJobStore.swift`

- [ ] Store active job ids in the app-group container.
- [ ] Restore active jobs when the extension reopens.
- [ ] Resume polling instead of creating duplicate jobs.
- [ ] Clear active jobs after success, failure, cancellation, or user deletion.

### Task 4: Add MP4 Result Handling

**Files:**
- Add: `Packages/PromptGIFCore/Sources/PromptGIFCore/Media/MP4FrameExtractor.swift`
- Modify: `Extensions/PromptGIFMessages/MessagesComposerModel.swift`

- [ ] Download MP4 provider results to the app-group cache.
- [ ] Extract frames with AVFoundation.
- [ ] Reuse `CaptionRenderer` and `GIFRenderer`.
- [ ] Add file-size checks for Messages insertion.

### Task 5: Add Real Provider Adapter

**Files:**
- Add: `Backend/src/providers/providerContract.mjs`
- Add: `Backend/src/providers/<providerName>.mjs`
- Modify: `Backend/src/server.mjs`
- Add tests under: `Backend/test`

- [ ] Define a provider contract for text-to-animation and image-to-animation.
- [ ] Implement the first real provider adapter.
- [ ] Keep provider credentials in environment variables only.
- [ ] Add adapter tests with mocked provider responses.
- [ ] Keep the fake provider available for local demos.

### Task 6: Harden Privacy and Safety

**Files:**
- Modify: `Backend/src/safety/moderation.mjs`
- Modify: `docs/PRIVACY_AND_SAFETY.md`
- Modify: `App/PromptGIF/AppShellView.swift`

- [ ] Add backend moderation provider integration.
- [ ] Add request retention and deletion controls.
- [ ] Add user-facing history deletion confirmation.
- [ ] Add production privacy policy text and App Store privacy nutrition notes.

### Task 7: App Store Readiness

**Files:**
- Modify: `project.yml`
- Modify: `App/PromptGIF/Info.plist`
- Modify: `Extensions/PromptGIFMessages/Info.plist`
- Modify: `docs/DEVELOPMENT.md`

- [ ] Finalize bundle ids, app group, signing, and icons.
- [ ] Add screenshots and metadata for the Messages extension.
- [ ] Test compact and expanded Messages modes on physical devices.
- [ ] Prepare App Review notes covering attachment insertion, manual sending, no sticker mode, and backend-mediated AI generation.
