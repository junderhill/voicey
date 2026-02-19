import AppKit
import SwiftUI
import VoiceyCore

@main
struct VoiceyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      SettingsView()
        .environmentObject(appDelegate.appState)
    }
  }
}
