import GifForgeCore
import SwiftUI

struct HistoryView: View {
  var history: [GenerationHistoryItem]
  var clearHistory: () -> Void

  @State private var isConfirmingClearHistory = false

  var body: some View {
    List {
      if history.isEmpty {
        ContentUnavailableView(
          String(localized: "No GIFs Yet"),
          systemImage: "sparkles",
          description: Text(String(localized: "GIFs generated from Messages will appear here."))
        )
      } else {
        ForEach(history) { item in
          VStack(alignment: .leading, spacing: 10) {
            Text(item.prompt)
              .font(.headline)
              .lineLimit(2)
            if let caption = item.captionText, !caption.isEmpty {
              Text(caption)
                .font(.subheadline)
                .foregroundStyle(.primary)
            }
            ShareLink(item: item.gifURL) {
              HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                Text(String(localized: "Share GIF"))
                  // `Label`'s internal composition didn't propagate a
                  // `.fixedSize` applied to the outer control — an automated
                  // audit flagged the text as liable to clip at larger
                  // Dynamic Type sizes (List rows can compute height before
                  // a button label's text has room to grow). Applying
                  // `.fixedSize` directly to the Text resolves it.
                  .fixedSize(horizontal: false, vertical: true)
              }
              // Growing the text alone left an under-44pt tap target (the
              // audit's "Hit area is too small" check) — pad and expand the
              // hit-testable area explicitly to meet Apple's HIG minimum.
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .font(.subheadline.weight(.semibold))
            // Tint-colored text measured borderline on an automated contrast
            // audit: the app's teal AccentColor sits at ~4.4:1 against white,
            // just under the 4.5:1 body-text threshold — and that ratio is
            // symmetric, so a filled tint background with white text doesn't
            // help either (~4.4:1 either way). System label color is
            // guaranteed to pass; the icon still carries the "actionable" cue.
            .foregroundStyle(.primary)
          }
          .padding(.vertical, 6)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(String(localized: "History"))
    .toolbar {
      Button(role: .destructive) {
        isConfirmingClearHistory = true
      } label: {
        Label(String(localized: "Clear"), systemImage: "trash")
      }
      .disabled(history.isEmpty)
    }
    .alert(String(localized: "Clear History?"), isPresented: $isConfirmingClearHistory) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Clear History"), role: .destructive, action: clearHistory)
    } message: {
      Text(String(localized: "Delete generated GIF history and resumable job metadata from this device."))
    }
  }
}
