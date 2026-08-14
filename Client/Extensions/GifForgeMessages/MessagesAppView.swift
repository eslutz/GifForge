import ImageIO
import PhotosUI
import GifForgeCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessagesAppView: View {
  @Bindable var model: MessagesComposerModel
  var insertGIF: (URL) -> Void
  var requestExpanded: () -> Void
  var openContainingApp: () -> Void

  @State private var selectedPhotoItem: PhotosPickerItem?
  @FocusState private var promptFocused: Bool

  @ScaledMetric(relativeTo: .largeTitle) private var emptyStateIconSize: CGFloat = 34
  @ScaledMetric private var statusDotSize: CGFloat = 7
  @ScaledMetric private var recentCardWidth: CGFloat = 120
  @ScaledMetric private var recentCardHeight: CGFloat = 86
  @ScaledMetric private var recentThumbnailSize: CGFloat = 40

  var body: some View {
    Group {
      if model.presentationStyle == .compact {
        compactBody
      } else {
        expandedBody
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(.systemBackground))
    .task {
      await model.loadRecent()
    }
    .alert(String(localized: "GifForge"), isPresented: Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .alert(String(localized: "Try again?"), isPresented: Binding(
      get: { model.retryPromptMessage != nil },
      set: { if !$0 { model.dismissRetryPrompt() } }
    )) {
      Button(String(localized: "Cancel"), role: .cancel) {
        model.cancelPendingRetry()
      }
      Button(String(localized: "Retry")) {
        model.retryGeneration()
      }
      .disabled(!model.canRetryGeneration)
    } message: {
      Text(model.retryPromptMessage ?? "")
    }
    .onChange(of: selectedPhotoItem) { _, newValue in
      guard let newValue else {
        model.setSourceImageData(nil)
        return
      }

      Task {
        guard let data = try? await newValue.loadTransferable(type: Data.self) else {
          return
        }

        applyPickedMedia(data: data, contentTypes: newValue.supportedContentTypes)
      }
    }
    .onChange(of: promptFocused) { _, isFocused in
      if isFocused, model.presentationStyle == .compact {
        requestExpanded()
      }
    }
  }

  /// Routes picked bytes to the right composer path by inspecting the content
  /// types PhotosPicker reports for the item, before any decoding happens —
  /// animated GIFs and MP4/MOV videos pass through as `SourceMedia` untouched;
  /// everything else is treated as a static photo.
  private func applyPickedMedia(data: Data, contentTypes: [UTType]) {
    if let movieType = contentTypes.first(where: { $0.conforms(to: .movie) }) {
      let mimeType = movieType.conforms(to: .quickTimeMovie) ? "video/quicktime" : "video/mp4"
      model.setSourceMedia(data: data, mimeType: mimeType, fileName: nil, kind: .video)
    } else if contentTypes.contains(where: { $0.conforms(to: .gif) }) {
      model.setSourceMedia(data: data, mimeType: "image/gif", fileName: nil, kind: .animatedGIF)
    } else {
      model.setSourceImageData(data)
    }
  }

  /// Compact fits Messages' ~220pt drawer: status, prompt, and primary actions only.
  /// Anything more promotes to the expanded presentation.
  private var compactBody: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        statusRow
        setupHint

        if let previewGIFURL = model.previewGIFURL {
          previewSurface(height: 120)

          Button {
            insertGIF(previewGIFURL)
          } label: {
            Label(String(localized: "Insert GIF"), systemImage: "arrow.up.message.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        } else {
          promptField

          HStack(spacing: 10) {
            mediaButton
            generateButton
          }

          plannerAvailabilityChip
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 12)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var expandedBody: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text(String(localized: "Create GIF"))
            .font(.title3.weight(.semibold))
          Spacer()
          statusRow
        }

        setupHint
        previewSurface(height: 230)

        VStack(alignment: .leading, spacing: 12) {
          promptEditor
          captionPicker
          captionControls

          HStack(spacing: 10) {
            mediaButton
            generateButton
          }

          plannerAvailabilityChip
        }

        if let previewGIFURL = model.previewGIFURL {
          HStack(spacing: 10) {
            Button {
              model.applyCaptionEdit()
            } label: {
              Label(String(localized: "Apply Caption"), systemImage: "text.bubble")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!model.canApplyCaptionEdit)

            Button {
              insertGIF(previewGIFURL)
            } label: {
              Label(String(localized: "Insert"), systemImage: "arrow.up.message.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
          }
        } else {
          recentSection
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 18)
      .padding(.bottom, 12)
    }
    .scrollDismissesKeyboard(.interactively)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var setupHint: some View {
    if model.needsContainingAppSetup {
      HStack(spacing: 10) {
        Image(systemName: "info.circle.fill")
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text(String(localized: "Open the GifForge app once to finish setup."))
          .font(.footnote)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button(String(localized: "Open")) {
          openContainingApp()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      .padding(10)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
      .accessibilityElement(children: .combine)
    }
  }

  /// Small, honest indicator of whether the next plan will run on Apple's
  /// on-device model or fall back to deterministic templates, and why.
  private var plannerAvailabilityChip: some View {
    HStack(spacing: 4) {
      Image(systemName: model.plannerAvailability.isOnDevice ? "cpu.fill" : "sparkle")
        .font(.caption2)
        .foregroundStyle(model.plannerAvailability.isOnDevice ? Color.accentColor : .secondary)
        .accessibilityHidden(true)
      Text(plannerAvailabilityLabel)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "Planning: \(plannerAvailabilityLabel)"))
  }

  private var plannerAvailabilityLabel: String {
    switch model.plannerAvailability {
    case .onDevice:
      String(localized: "Planned on-device")
    case let .unavailable(reason):
      reason.displayMessage
    }
  }

  private var promptField: some View {
    TextField(String(localized: "Describe a GIF"), text: $model.prompt)
      .font(.body)
      .submitLabel(.done)
      .focused($promptFocused)
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
  }

  private var promptEditor: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.secondarySystemBackground))

      if model.prompt.isEmpty {
        Text(String(localized: "Describe the GIF you want"))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
          .accessibilityHidden(true)
      }

      TextEditor(text: $model.prompt)
        .font(.body)
        .focused($promptFocused)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
    .frame(minHeight: 104)
    .accessibilityLabel(String(localized: "GIF description"))
  }

  private var captionPicker: some View {
    Picker(String(localized: "Caption"), selection: $model.captionMode) {
      ForEach(CaptionMode.allCases) { mode in
        Text(mode.displayName).tag(mode)
      }
    }
    .pickerStyle(.segmented)
  }

  private var mediaButton: some View {
    PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos])) {
      Label(mediaButtonTitle, systemImage: mediaButtonIcon)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .controlSize(.large)
  }

  private var mediaButtonTitle: String {
    switch model.selectedMediaKind {
    case .none:
      String(localized: "Add Media")
    case .image:
      String(localized: "Photo Added")
    case .animatedGIF:
      String(localized: "GIF Added")
    case .video:
      String(localized: "Video Added")
    }
  }

  private var mediaButtonIcon: String {
    switch model.selectedMediaKind {
    case .none:
      "photo.on.rectangle"
    case .image:
      "photo.fill"
    case .animatedGIF:
      "photo.stack.fill"
    case .video:
      "video.fill"
    }
  }

  private var generateButton: some View {
    Button {
      if model.presentationStyle == .compact {
        requestExpanded()
      }
      model.generate()
    } label: {
      Label(String(localized: "Generate"), systemImage: "sparkles")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .disabled(!model.canGenerate)
  }

  @ViewBuilder
  private var captionControls: some View {
    switch model.captionMode {
    case .none:
      EmptyView()
    case .userText:
      TextField(String(localized: "Caption text"), text: $model.explicitCaption)
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    case .suggestWithAI:
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          TextField(String(localized: "Selected caption"), text: $model.selectedCaption)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

          Button {
            model.requestCaptionSuggestions()
          } label: {
            Label(String(localized: "Suggest"), systemImage: "wand.and.stars")
              .labelStyle(.iconOnly)
              .padding(6)
          }
          .buttonStyle(.bordered)
          .accessibilityLabel(String(localized: "Suggest caption"))
        }

        if !model.captionSuggestions.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(model.captionSuggestions) { suggestion in
                Button(suggestion.text) {
                  model.selectedCaption = suggestion.text
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func previewSurface(height: CGFloat) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 18)
        .fill(Color(.secondarySystemBackground))

      if let previewGIFURL = model.previewGIFURL {
        AnimatedGIFView(url: previewGIFURL)
          .clipShape(RoundedRectangle(cornerRadius: 18))
          .accessibilityLabel(String(localized: "Animated GIF preview: \(model.prompt)"))
      } else if let data = model.sourceImageData, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .clipShape(RoundedRectangle(cornerRadius: 18))
          .accessibilityLabel(String(localized: "Selected photo"))
      } else if model.selectedMediaKind == .animatedGIF, let url = model.selectedMediaPreviewURL {
        AnimatedGIFView(url: url)
          .clipShape(RoundedRectangle(cornerRadius: 18))
          .accessibilityLabel(String(localized: "Selected animated GIF"))
      } else if model.selectedMediaKind == .video {
        VStack(spacing: 10) {
          Image(systemName: "video.fill")
            .font(.system(size: emptyStateIconSize, weight: .medium))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)

          Text(String(localized: "Video selected"))
            .font(.headline)
          Text(String(localized: "GifForge will transform this video into a GIF."))
            .font(.subheadline)
            // .subheadline+.secondary measured borderline on the containing
            // app's automated contrast audit for the same text/size class;
            // applied consistently here (no XCUITest harness reaches the
            // extension target to verify directly).
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Selected video. GifForge will transform this video into a GIF."))
      } else {
        VStack(spacing: 10) {
          Image(systemName: "sparkles.rectangle.stack")
            .font(.system(size: emptyStateIconSize, weight: .medium))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)

          Text(String(localized: "Ready to make a GIF"))
            .font(.headline)
          Text(String(localized: "Start with a prompt, then add a photo if you want."))
            .font(.subheadline)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .overlay(alignment: .topTrailing) {
      if model.selectedMediaKind != .none, model.previewGIFURL == nil {
        Label(mediaBadgeText, systemImage: "checkmark.circle.fill")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.regularMaterial, in: Capsule())
          .padding(10)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 18))
  }

  private var mediaBadgeText: String {
    switch model.selectedMediaKind {
    case .none:
      ""
    case .image:
      String(localized: "Photo")
    case .animatedGIF:
      String(localized: "GIF")
    case .video:
      String(localized: "Video")
    }
  }

  private var statusRow: some View {
    HStack(spacing: 6) {
      if case let .rendering(frame, total) = model.renderProgress, total > 0 {
        ProgressView(value: Double(frame), total: Double(total))
          .frame(width: 60)
      } else if model.isWorking {
        ProgressView()
          .controlSize(.small)
      } else {
        Circle()
          .fill(model.phase == .preview ? Color.green : Color.secondary.opacity(0.45))
          .frame(width: statusDotSize, height: statusDotSize)
          .accessibilityHidden(true)
      }
      Text(model.phase.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(.secondarySystemBackground), in: Capsule())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "Status: \(model.phase.title)"))
  }

  @ViewBuilder
  private var recentSection: some View {
    if !model.recentItems.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(String(localized: "Recent"))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(model.recentItems) { item in
              Button {
                model.previewGIFURL = item.gifURL
                model.phase = .preview
              } label: {
                VStack(alignment: .leading, spacing: 8) {
                  RecentThumbnailView(url: item.gifURL, size: recentThumbnailSize)
                  Text(item.prompt)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(width: recentCardWidth - 24, alignment: .leading)
                }
                .padding(10)
                .frame(width: recentCardWidth, height: recentCardHeight, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
              }
              .buttonStyle(.plain)
              .accessibilityLabel(String(localized: "Recent GIF: \(item.prompt)"))
            }
          }
        }
      }
    }
  }
}

/// Decodes and caches a GIF's first frame as a small static thumbnail, replacing
/// the generic "film.stack" glyph history cards used to show. Decoding is
/// off-main and only happens once per file URL (SwiftUI's `.task(id:)` re-runs
/// only when the id changes, and this view's own identity is stable across
/// re-renders of its parent list).
private struct RecentThumbnailView: View {
  var url: URL
  var size: CGFloat

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "film.stack")
          .font(.title3)
          .foregroundStyle(.tint)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
    .task(id: url) {
      image = await Self.decodeFirstFrame(of: url)
    }
  }

  private static func decodeFirstFrame(of url: URL) async -> UIImage? {
    await Task.detached(priority: .utility) {
      firstFrame(of: url)
    }.value
  }
}

/// Animated GIF preview backed by ImageIO's frame-by-frame animation callback —
/// no WKWebView (and its separate web content process) inside the extension.
/// Honors Reduce Motion by showing the first frame with tap-to-play.
private struct AnimatedGIFView: UIViewRepresentable {
  var url: URL

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeUIView(context: Context) -> AnimatedGIFUIView {
    AnimatedGIFUIView()
  }

  func updateUIView(_ view: AnimatedGIFUIView, context: Context) {
    view.configure(url: url, autoplay: !reduceMotion)
  }
}

final class AnimatedGIFUIView: UIView {
  private let imageView = UIImageView()
  private var currentURL: URL?
  private var autoplay = true
  private var animationToken: AnimationToken?

  private final class AnimationToken {
    var isCancelled = false
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    isAccessibilityElement = true
    accessibilityTraits = .image
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // No deinit cancellation needed: the animation block captures self weakly and
  // stops itself on the first callback after the view deallocates.

  func configure(url: URL, autoplay: Bool) {
    guard url != currentURL || autoplay != self.autoplay else {
      return
    }

    currentURL = url
    self.autoplay = autoplay
    stopAnimation()

    if autoplay {
      startAnimation(url: url)
    } else {
      imageView.image = firstFrame(of: url)
    }
  }

  @objc private func handleTap() {
    guard let currentURL, animationToken == nil else {
      return
    }

    startAnimation(url: currentURL)
  }

  private func startAnimation(url: URL) {
    let token = AnimationToken()
    animationToken = token
    CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] _, cgImage, stop in
      guard let self, !token.isCancelled else {
        stop.pointee = true
        return
      }

      self.imageView.image = UIImage(cgImage: cgImage)
    }
  }

  private func stopAnimation() {
    animationToken?.isCancelled = true
    animationToken = nil
  }
}

/// Decodes just the first frame of a GIF/animated image file. Shared by the
/// preview's Reduce-Motion static state and the recents-list thumbnails.
private func firstFrame(of url: URL) -> UIImage? {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else {
    return nil
  }

  return UIImage(cgImage: cgImage)
}
