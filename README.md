# Gifster

Gifster is an iOS 26.5+ iMessage app extension scaffold for generating custom animated GIFs with AI and inserting the finished GIF into Messages as a normal attachment.

The v1 architecture is deliberately provider-neutral:

- The iOS app and Messages extension never call external AI media providers directly.
- Apple Foundation Models are the local planning layer where available.
- The backend owns moderation, provider credentials, provider-specific translation, job state, and temporary result URLs.
- The app renders visible caption text locally and converts the generated motion result into the final GIF.
- Messages insertion uses attachment insertion only. The user manually sends the message.

## Repository Layout

- `project.yml` - XcodeGen project for the containing iOS app and Messages extension.
- `App/Gifster` - containing app SwiftUI UI for onboarding, privacy, history, and settings.
- `Extensions/GifsterMessages` - iMessage extension UI and attachment insertion flow.
- `Packages/GifsterCore` - shared Swift package for planning models, backend client, image preprocessing, GIF rendering, and history.
- `Backend` - fake/demo backend with provider abstraction and job polling endpoints.
- `docs` - product, architecture, privacy, roadmap, spike, and implementation plan.

## Quick Start

```bash
xcodegen generate
cd Packages/GifsterCore
swift test --scratch-path /private/tmp/gifster-swiftpm
cd ../../Backend
npm test
npm start
```

The local backend listens at `http://127.0.0.1:8787` by default. The containing app Settings screen stores the backend URL in the shared app-group defaults used by the Messages extension.

## Current Toolchain Note

This project is configured for iOS 26.5+ and has been verified with Xcode 26.5 and the iOS 26.5 SDK. The scaffold keeps the Apple Foundation Models integration boundary explicit and provides a deterministic local fallback for development.

## Documentation

- [Product Overview](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Backend API](docs/API.md)
- [Privacy and Safety](docs/PRIVACY_AND_SAFETY.md)
- [Development and Demo Setup](docs/DEVELOPMENT.md)
- [Image Playground Spike](docs/spikes/image-playground-feasibility.md)
- [Roadmap](docs/ROADMAP.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)
