import SwiftUI
import VoiceyCore

@main
struct VoiceyKeyboardApp: App {
  init() {
    // Wire up ModelManager notifications for the iOS host app
    ModelManager.shared.onDownloadComplete = { model in
      AppLogger.model.info("Model \(model.displayName) downloaded successfully")
    }
    ModelManager.shared.onDownloadFailed = { reason in
      AppLogger.model.error("Model download failed: \(reason)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
