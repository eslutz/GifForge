import SwiftUI

struct PrivacyDetailsView: View {
  var body: some View {
    Form {
      Section(String(localized: "Generation")) {
        Text(String(localized: "Prompts and selected images are sent through the configured GifForge service to create media."))
        Text(String(localized: "Caption cleanup and prompt planning run locally when Apple Foundation Models are available."))
      }

      Section(String(localized: "On This Device")) {
        Text(String(localized: "Generated GIFs and resumable job metadata are stored locally only as needed."))
        Text(String(localized: "Use History to delete generated GIF history and resumable job data from this device."))
      }

      Section(String(localized: "Messages")) {
        Text(String(localized: "GifForge inserts a preview into Messages. You choose when to send it."))
      }
    }
    .formStyle(.grouped)
    .navigationTitle(String(localized: "Data Handling"))
    .navigationBarTitleDisplayMode(.inline)
  }
}
