# GifForge Implementation Plan Execution Ledger

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to continue this plan task-by-task. Treat checked items as implemented only when current repo evidence still proves them.

**Goal:** Build GifForge into an App Store-ready iOS 26.5+ iMessage GIF generation app.

**Architecture:** The Messages extension owns the primary user flow while the containing app owns onboarding, settings, and local history. Shared Swift package code owns models, planning, networking, media rendering, and storage. The backend owns validation, moderation, provider abstraction, credentials, job state, and temporary result URLs.

**Current tech stack:** SwiftUI, Messages framework, PhotosUI, ImageIO, CoreGraphics, Apple Foundation Models when available, XcodeGen, Swift Package Manager, ASP.NET Core Minimal API on .NET 10 with Native AOT, xUnit, Azure Container Apps, Azure Table/Queue/Blob Storage, Bicep, and GHCR.

## Phase 1: Scaffold and Demo Loop

Evidence: `Client/project.yml`, `Client/Packages/GifForgeCore`, `Client/App/GifForge`, `Client/Extensions/GifForgeMessages`, `Backend`, `Backend.Tests`, `infra`, `.github/workflows`, and `Documentation/DEVELOPMENT.md`.

- [x] Target iOS 26.5 in `Client/project.yml` and `Client/Packages/GifForgeCore/Package.swift`.
- [x] Generate and track the Xcode project under `Client/GifForge.xcodeproj`.
- [x] Build the containing app with onboarding, privacy, history, and backend settings.
- [x] Build the Messages extension with compact and expanded SwiftUI surfaces.
- [x] Use `PhotosPicker` for user-selected images only.
- [x] Submit all generation jobs through the backend.
- [x] Use the backend fake provider for the deterministic demo loop.
- [x] Render captions locally and create the final GIF with ImageIO.
- [x] Insert the GIF into Messages with attachment insertion only.

## Phase 2: Foundation Models Integration

Evidence: `FoundationModelsPromptPlanner`, `LocalPromptPlanner`, `PromptPlannerTests`, and Messages caption controls.

- [x] Use Apple Foundation Models guided generation on iOS/macOS 26+ when available.
- [x] Keep deterministic fallback planning for Simulator, CI, unsupported OS versions, unavailable Apple Intelligence, and local-model errors.
- [x] Maintain structured output for prompt planning and caption suggestions.
- [x] Preserve explicit captions unless unsafe or too long.
- [x] Let users review, select, and edit suggested captions.
- [x] Keep provider prompts free of visible readable caption text because captions are rendered locally.
- [ ] Add image-understanding support only after Apple exposes an extension-safe path for it.

## Phase 3: Production Backend

Evidence: `Backend/GifForge.Backend.csproj`, `Backend/Program.cs`, `Backend/Jobs`, `Backend/Queueing`, `Backend/Security`, `Backend/Storage`, `Backend/Safety`, `Backend/Operations`, `Backend.Tests`, `infra/main.bicep`, `infra/main.subscription.bicep`, and deployment workflows.

- [x] Replace the original Node placeholder direction with ASP.NET Core Minimal API on .NET 10.
- [x] Configure Native AOT publish settings.
- [x] Use xUnit for backend tests.
- [x] Validate generation requests before provider submission.
- [x] Require App Attest for deployed environments and fail closed unless explicitly configured or demo bypass is enabled for controlled nonprod smoke testing.
- [x] Store durable generation job state in Azure Table Storage.
- [x] Store App Attest challenge/session state in Azure Table Storage so API replicas can scale and restart.
- [x] Use Azure Queue Storage for long-running provider orchestration and retryable transient failures.
- [x] Store provider outputs and temporary assets in Azure Blob Storage.
- [x] Run API and worker as separate Azure Container Apps from the same image.
- [x] Add request/result retention, expired-job `410 Gone`, expired-row cleanup, and temporary blob lifecycle deletion.
- [x] Add metadata-only operational generation lifecycle logging without prompt text, caption text, image bytes, provider result bytes, or provider error messages.
- [x] Provide Bicep templates for nonprod/prod resources.
- [x] Default nonprod scale settings to `minReplicas=0` and `workerMinReplicas=0`.
- [x] Provide dry-run-first Azure OIDC setup for `nonprod` and `prod`.
- [x] Add manual `Deploy Nonprod` and guarded `Deploy Prod` workflows.
- [x] Guard scale-to-zero and production deploy safety settings through focused workflow and infrastructure validation.
- [ ] Apply GitHub OIDC setup and capture successful workflow-dispatch evidence for nonprod.
- [ ] Apply production OIDC/provider/App Attest secrets and capture successful production deploy evidence.

## Phase 4: Provider Adapter

Evidence: `Backend/Providers`, `ExternalHttpGenerationProviderTests`, `Documentation/API.md`, `Documentation/ARCHITECTURE.md`, and `infra` provider parameters.

- [x] Keep the fake provider available for local demos and nonprod smoke testing.
- [x] Define the backend provider contract for text-to-animation, image-to-animation, and result download.
- [x] Implement the provider-neutral `external-http` adapter for a compatible gateway or vendor-specific wrapper.
- [x] Keep provider credentials server-side through environment variables and Container Apps secrets.
- [x] Support MP4 or frame-sequence provider outputs, not final captioned GIF output.
- [x] Add adapter tests with mocked provider responses.
- [ ] Select and integrate the first paid/real AI media provider after provider choice and credentials are available.

## Phase 5: GIF Quality

Evidence: `MP4FrameExtractor`, `MotionAssetFrameRenderer`, `CaptionRenderer`, `GIFRenderer`, `GIFPipelineTests`, and Messages composer rendering flow.

- [x] Download provider results to app-controlled cache locations.
- [x] Extract MP4 frames with AVFoundation.
- [x] Handle frame-sequence JSON and direct MP4 payloads through `GeneratedMotionAsset`.
- [x] Reuse local caption rendering and GIF rendering for all provider result types.
- [x] Enforce Messages-oriented frame-count, dimension, and file-size limits.
- [x] Preserve total animation duration when frame sampling reduces frame count.
- [x] Wrap and fit longer caption text locally before GIF creation.
- [x] Let caption edits re-render locally without another provider generation request.

## Phase 6: App Store Readiness

Evidence: `Documentation/APP_STORE_READINESS.md`, `Documentation/DEVICE_AND_APP_STORE_TEST_PLAN.md`, `Documentation/APP_STORE_METADATA.md`, `Documentation/APP_REVIEW_NOTES.md`, `Documentation/PRIVACY_POLICY.md`, `scripts/validate-client-signing.rb`, and `Client/Tests/GifForgeUITests`.

- [x] Maintain App Store readiness, metadata, privacy policy, and review-note drafts under `Documentation/`.
- [x] Add production privacy policy text and App Store privacy-answer notes.
- [x] Add user-facing history deletion confirmation.
- [x] Add UI test coverage for containing app navigation, settings, and history clear confirmation.
- [x] Add client signing validation guard for bundle ids, App Groups, and App Attest entitlements.
- [x] Add tracked containing-app and Messages-extension icon assets.
- [x] Document physical-device and App Store evidence collection.
- [x] Document attachment insertion, manual sending, no sticker mode, backend-mediated provider calls, and no Image Playground dependency for App Review.
- [ ] Finalize production bundle ids, App Group, signing, and icons in the Apple Developer portal.
- [ ] Capture screenshots and final App Store Connect metadata.
- [ ] Test compact and expanded Messages modes on physical devices.
- [ ] Validate production App Attest on a physical device.
- [ ] Preserve production deployment and health-check evidence.

## Current Blockers Before App Store-Ready

- Physical iMessage extension testing requires a device and Apple Developer signing state.
- Production App Attest validation requires configured Apple Developer capabilities, backend App Attest root/app identifier values, and a physical device.
- Production deploy proof requires `prod` GitHub environment secrets, Azure OIDC setup, selected external provider settings, and an immutable GHCR image tag.
- A real paid media provider cannot be integrated until the provider is selected and credentials/contract details are available.
