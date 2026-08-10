import PhotosUI
import GifForgeCore
import SwiftUI
import UIKit
import WebKit

struct MessagesAppView: View {
  @Bindable var model: MessagesComposerModel
  var insertGIF: (URL) -> Void

  @State private var selectedPhotoItem: PhotosPickerItem?

  var body: some View {
    Group {
      if model.presentationStyle == .compact {
        compactBody
      } else {
        expandedBody
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, 16)
    .padding(.top, 18)
    .padding(.bottom, 12)
    .background(Color(.systemBackground))
    .task {
      await model.loadRecent()
    }
    .alert("GifForge", isPresented: Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .alert("Try again?", isPresented: Binding(
      get: { model.retryPromptMessage != nil },
      set: { if !$0 { model.dismissRetryPrompt() } }
    )) {
      Button("Cancel", role: .cancel) {
        model.cancelPendingRetry()
      }
      Button("Retry") {
        model.retryGeneration()
      }
      .disabled(!model.canRetryGeneration)
    } message: {
      Text(model.retryPromptMessage ?? "")
    }
    .onChange(of: selectedPhotoItem) { _, newValue in
      Task {
        let data = try? await newValue?.loadTransferable(type: Data.self)
        model.setSourceImageData(data ?? nil)
      }
    }
  }

  private var compactBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      statusRow

      if let previewGIFURL = model.previewGIFURL {
        previewSurface(height: 150)

        Button {
          insertGIF(previewGIFURL)
        } label: {
          Label("Insert GIF", systemImage: "arrow.up.message.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      } else {
        promptField

        HStack(spacing: 10) {
          photoButton(title: model.hasImage ? "Photo Added" : "Add Photo")
          generateButton
        }

        captionPicker
        captionControls

        if model.hasImage {
          selectedImagePreview
        } else {
          recentSection
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var expandedBody: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("Create GIF")
            .font(.title3.weight(.semibold))
          Spacer()
          statusRow
        }

        previewSurface(height: 230)

        VStack(alignment: .leading, spacing: 12) {
          promptEditor
          captionPicker
          captionControls

          HStack(spacing: 10) {
            photoButton(title: model.hasImage ? "Change Photo" : "Add Photo")
            generateButton
          }
        }

        if let previewGIFURL = model.previewGIFURL {
          HStack(spacing: 10) {
            Button {
              model.applyCaptionEdit()
            } label: {
              Label("Apply Caption", systemImage: "text.bubble")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!model.canApplyCaptionEdit)

            Button {
              insertGIF(previewGIFURL)
            } label: {
              Label("Insert", systemImage: "arrow.up.message.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
          }
        } else {
          recentSection
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var promptField: some View {
    TextField("Describe a GIF", text: $model.prompt)
      .font(.body)
      .submitLabel(.done)
      .padding(.horizontal, 14)
      .frame(height: 50)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
      .overlay(
        RoundedRectangle(cornerRadius: 14)
          .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
      )
  }

  private var promptEditor: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.secondarySystemBackground))
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)

      if model.prompt.isEmpty {
        Text("Describe the GIF you want")
          .foregroundStyle(.secondary)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
      }

      TextEditor(text: $model.prompt)
        .font(.body)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
    .frame(minHeight: 104)
  }

  private var captionPicker: some View {
    Picker("Caption", selection: $model.captionMode) {
      ForEach(CaptionMode.allCases) { mode in
        Text(mode.displayName).tag(mode)
      }
    }
    .pickerStyle(.segmented)
  }

  private func photoButton(title: String) -> some View {
    let hasImage = model.hasImage
    return PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
      Label(title, systemImage: hasImage ? "photo.fill" : "photo")
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .controlSize(.large)
  }

  private var generateButton: some View {
    Button {
      model.generate()
    } label: {
      Label("Generate", systemImage: "sparkles")
        .lineLimit(1)
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
      TextField("Caption text", text: $model.explicitCaption)
        .font(.body)
        .textFieldStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
          RoundedRectangle(cornerRadius: 14)
            .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
    case .suggestWithAI:
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          TextField("Selected caption", text: $model.selectedCaption)
            .font(.body)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
              RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            )

          Button {
            model.requestCaptionSuggestions()
          } label: {
            Label("Suggest", systemImage: "wand.and.stars")
              .labelStyle(.iconOnly)
              .frame(width: 46, height: 46)
          }
          .buttonStyle(.bordered)
          .accessibilityLabel("Suggest caption")
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
        GIFPreviewView(url: previewGIFURL)
          .clipShape(RoundedRectangle(cornerRadius: 18))
      } else if let data = model.sourceImageData, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .clipShape(RoundedRectangle(cornerRadius: 18))
      } else {
        VStack(spacing: 10) {
          Image(systemName: "sparkles.rectangle.stack")
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(.tint)

          Text("Ready to make a GIF")
            .font(.headline)
          Text("Start with a prompt, then add a photo if you want.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .padding(.horizontal, 24)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .overlay(alignment: .topTrailing) {
      if model.hasImage && model.previewGIFURL == nil {
        Label("Photo", systemImage: "checkmark.circle.fill")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.regularMaterial, in: Capsule())
          .padding(10)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 18))
  }

  @ViewBuilder
  private var selectedImagePreview: some View {
    if let data = model.sourceImageData, let image = UIImage(data: data) {
      HStack(spacing: 12) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 58, height: 58)
          .clipShape(RoundedRectangle(cornerRadius: 12))

        VStack(alignment: .leading, spacing: 3) {
          Text("Photo added")
            .font(.subheadline.weight(.semibold))
          Text("Generate will animate this image.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(10)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
  }

  private var statusRow: some View {
    HStack(spacing: 6) {
      if model.phase == .planning || model.phase == .submitting || model.phase == .generating || model.phase == .rendering {
        ProgressView()
          .controlSize(.small)
      } else {
        Circle()
          .fill(model.phase == .preview ? Color.green : Color.secondary.opacity(0.45))
          .frame(width: 7, height: 7)
      }
      Text(model.phase.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(.secondarySystemBackground), in: Capsule())
  }

  @ViewBuilder
  private var recentSection: some View {
    if !model.recentItems.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Recent")
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
                  Image(systemName: "film.stack")
                    .font(.title3)
                    .foregroundStyle(.tint)
                  Text(item.prompt)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(width: 96, alignment: .leading)
                }
                .padding(10)
                .frame(width: 120, height: 86, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }
}

private struct GIFPreviewView: UIViewRepresentable {
  var url: URL

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView()
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = false
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
  }
}
