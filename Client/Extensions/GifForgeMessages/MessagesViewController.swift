import Messages
import GifForgeCore
import SwiftUI
import UIKit

final class MessagesViewController: MSMessagesAppViewController {
  private let model = MessagesComposerModel()
  private var hostingController: UIHostingController<MessagesAppView>?

  override func viewDidLoad() {
    super.viewDidLoad()
    #if DEBUG
    AppStorageDirectories.assertSharedStorageConfigured()
    #endif
    model.presentationStyle = presentationStyle
    installSwiftUIView()
  }

  override func didBecomeActive(with conversation: MSConversation) {
    super.didBecomeActive(with: conversation)
    model.prepareForForeground()
    Task {
      await model.restoreDraftIfNeeded()
      await model.loadRecent()
      await model.resumeActiveJobIfNeeded()
    }
  }

  override func willResignActive(with conversation: MSConversation) {
    super.willResignActive(with: conversation)
    model.handleWillResignActive()
  }

  override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
    super.willTransition(to: presentationStyle)
    model.presentationStyle = presentationStyle
  }

  private func installSwiftUIView() {
    let rootView = MessagesAppView(
      model: model,
      insertGIF: { [weak self, weak model] gifURL in
        self?.activeConversation?.insertAttachment(gifURL, withAlternateFilename: "GifForge.gif") { error in
          Task { @MainActor in
            if let error {
              model?.errorMessage = error.gifforgeUserFacingMessage
            } else {
              model?.clearDraftAfterInsert()
            }
          }
        }
      },
      requestExpanded: { [weak self] in
        guard let self, self.presentationStyle != .expanded else {
          return
        }

        self.requestPresentationStyle(.expanded)
      },
      openContainingApp: { [weak self] in
        guard let url = URL(string: "gifforge://setup") else {
          return
        }

        self?.extensionContext?.open(url, completionHandler: nil)
      }
    )

    let controller = UIHostingController(rootView: rootView)
    addChild(controller)
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      controller.view.topAnchor.constraint(equalTo: view.topAnchor),
      controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    controller.didMove(toParent: self)
    hostingController = controller
  }
}
