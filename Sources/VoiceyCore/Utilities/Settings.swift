import Foundation
#if os(macOS)
import ServiceManagement
#endif
import os

/// Manages user settings and preferences
public final class SettingsManager {
  public static let shared = SettingsManager()

  /// Use a specific suite to ensure consistent storage regardless of how app is launched
  private let defaults: UserDefaults

  private init() {
    #if os(iOS)
    // On iOS, use App Group suite for sharing between host app and keyboard extension
    if let suite = UserDefaults(suiteName: "group.work.voicey.Voicey") {
      defaults = suite
    } else {
      defaults = UserDefaults.standard
    }
    #else
    if let suite = UserDefaults(suiteName: "work.voicey.Voicey") {
      defaults = suite
    } else {
      defaults = UserDefaults.standard
    }
    #endif
    registerDefaults()
  }

  private func registerDefaults() {
    defaults.register(defaults: [
      Keys.selectedModel: ModelManager.fastModel.rawValue,
      Keys.launchAtLogin: false,
      Keys.showDockIcon: false,
      Keys.autoPasteEnabled: false,
      Keys.restoreClipboardAfterPaste: true,
      Keys.voiceCommandsEnabled: false,
      Keys.enableDetailedLogging: false,
      Keys.hasCompletedOnboarding: false
    ])
  }

  // MARK: - Keys

  private enum Keys {
    static let selectedModel = "selectedModel"
    static let launchAtLogin = "launchAtLogin"
    static let showDockIcon = "showDockIcon"
    static let autoPasteEnabled = "autoPasteEnabled"
    static let restoreClipboardAfterPaste = "restoreClipboardAfterPaste"
    static let voiceCommandsEnabled = "voiceCommandsEnabled"
    static let voiceCommands = "voiceCommands"
    static let enableDetailedLogging = "enableDetailedLogging"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
  }

  // MARK: - Model

  public var selectedModel: WhisperModel {
    get {
      let storedValue = defaults.string(forKey: Keys.selectedModel) ?? ""
      return WhisperModel(rawValue: storedValue) ?? .largeTurbo
    }
    set {
      defaults.set(newValue.rawValue, forKey: Keys.selectedModel)
    }
  }

  // MARK: - App Behavior

  public var launchAtLogin: Bool {
    get { defaults.bool(forKey: Keys.launchAtLogin) }
    set {
      defaults.set(newValue, forKey: Keys.launchAtLogin)
      configureLaunchAtLogin(enabled: newValue)
    }
  }

  public var showDockIcon: Bool {
    get { defaults.bool(forKey: Keys.showDockIcon) }
    set { defaults.set(newValue, forKey: Keys.showDockIcon) }
  }

  public var autoPasteEnabled: Bool {
    get { defaults.bool(forKey: Keys.autoPasteEnabled) }
    set { defaults.set(newValue, forKey: Keys.autoPasteEnabled) }
  }

  public var restoreClipboardAfterPaste: Bool {
    get { defaults.bool(forKey: Keys.restoreClipboardAfterPaste) }
    set { defaults.set(newValue, forKey: Keys.restoreClipboardAfterPaste) }
  }

  public func configureLaunchAtLogin(enabled: Bool) {
    #if os(macOS)
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      AppLogger.general.error("Failed to configure launch at login: \(error)")
    }
    #endif
  }

  // MARK: - Voice Commands

  public var voiceCommandsEnabled: Bool {
    get { defaults.bool(forKey: Keys.voiceCommandsEnabled) }
    set { defaults.set(newValue, forKey: Keys.voiceCommandsEnabled) }
  }

  public var voiceCommands: [VoiceCommand] {
    get {
      guard let data = defaults.data(forKey: Keys.voiceCommands),
        let commands = try? JSONDecoder().decode([VoiceCommand].self, from: data)
      else {
        return VoiceCommand.defaults
      }
      return commands
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        defaults.set(data, forKey: Keys.voiceCommands)
      }
    }
  }

  // MARK: - Debugging

  public var enableDetailedLogging: Bool {
    get { defaults.bool(forKey: Keys.enableDetailedLogging) }
    set { defaults.set(newValue, forKey: Keys.enableDetailedLogging) }
  }

  // MARK: - Onboarding

  public var hasCompletedOnboarding: Bool {
    get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
    set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
  }

  // MARK: - Reset

  public func resetToDefaults() {
    let domain = Bundle.main.bundleIdentifier ?? "com.voicey"
    defaults.removePersistentDomain(forName: domain)
    defaults.synchronize()
    registerDefaults()
  }
}
