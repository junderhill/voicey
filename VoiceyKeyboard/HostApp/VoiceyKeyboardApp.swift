import SwiftUI
import VoiceyCore

@main
struct VoiceyKeyboardApp: App {
  @StateObject private var bgService = BackgroundDictationService.shared
  @Environment(\.scenePhase) private var scenePhase
  @State private var showDictation = false

  init() {
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
        .fullScreenCover(isPresented: $showDictation) {
          DictationView()
        }
        .onAppear {
          PersistentAudioCapture.shared.startEngine()
          bgService.start()
          bgService.preloadModel()
        }
        .onChange(of: scenePhase) { newPhase in
          if newPhase == .active {
            PersistentAudioCapture.shared.startEngine()
          }
        }
        .onOpenURL { url in
          guard url.scheme == DictationBridge.urlScheme,
                url.host == DictationBridge.dictateHost else { return }
          AppLogger.general.info("Host app opened via dictation deep link")
          showDictation = true
        }
    }
  }
}
