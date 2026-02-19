import Foundation

/// Localization utility for accessing translated strings
/// Falls back to English if the user's language is not supported
///
/// Supported languages: English, Spanish, German, French, Japanese, Chinese (Simplified)
public enum L10n {
    public static let supportedLanguages = ["en", "es", "de", "fr", "ja", "zh-Hans"]

    public static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, tableName: "Localizable", bundle: Bundle.main, comment: "")
        if args.isEmpty {
            return format
        }
        return String(format: format, arguments: args)
    }

    // MARK: - App General

    public enum App {
        public static var name: String { L10n.string("app.name") }
        public static var tagline: String { L10n.string("app.tagline") }
    }

    // MARK: - Transcription States

    public enum State {
        public static var ready: String { L10n.string("state.ready") }
        public static var loadingModel: String { L10n.string("state.loadingModel") }
        public static var listening: String { L10n.string("state.listening") }
        public static var transcribing: String { L10n.string("state.transcribing") }
        public static var done: String { L10n.string("state.done") }
        public static func error(_ message: String) -> String { L10n.string("state.error", message) }
    }

    // MARK: - Model Status

    public enum ModelStatus {
        public static var noModel: String { L10n.string("modelStatus.noModel") }
        public static var loading: String { L10n.string("modelStatus.loading") }
        public static var ready: String { L10n.string("modelStatus.ready") }
        public static func error(_ message: String) -> String { L10n.string("modelStatus.error", message) }
    }

    // MARK: - Menu Items

    public enum Menu {
        public static var startTranscription: String { L10n.string("menu.startTranscription") }
        public static var stopTranscription: String { L10n.string("menu.stopTranscription") }
        public static var settings: String { L10n.string("menu.settings") }
        public static var checkForUpdates: String { L10n.string("menu.checkForUpdates") }
        public static var about: String { L10n.string("menu.about") }
        public static var quit: String { L10n.string("menu.quit") }
    }

    // MARK: - Tooltips

    public enum Tooltip {
        public static var noModelDownloaded: String { L10n.string("tooltip.noModelDownloaded") }
        public static var loadingModel: String { L10n.string("tooltip.loadingModel") }
        public static var ready: String { L10n.string("tooltip.ready") }
        public static func error(_ message: String) -> String { L10n.string("tooltip.error", message) }
    }

    // MARK: - Settings Tabs

    public enum Settings {
        public static var setup: String { L10n.string("settings.setup") }
        public static var general: String { L10n.string("settings.general") }
        public static var hotkey: String { L10n.string("settings.hotkey") }
        public static var audio: String { L10n.string("settings.audio") }
        public static var model: String { L10n.string("settings.model") }
        public static var voiceCommands: String { L10n.string("settings.voiceCommands") }
        public static var advanced: String { L10n.string("settings.advanced") }
    }

    // MARK: - Setup View

    public enum Setup {
        public static var downloadModel: String { L10n.string("setup.downloadModel") }
        public static func downloadModelDesc(_ modelName: String) -> String {
            L10n.string("setup.downloadModelDesc", modelName)
        }
        public static var downloadQualityModel: String { L10n.string("setup.downloadQualityModel") }
        public static func downloadQualityModelDesc(_ modelName: String) -> String {
            L10n.string("setup.downloadQualityModelDesc", modelName)
        }
        public static var microphoneAccess: String { L10n.string("setup.microphoneAccess") }
        public static var microphoneAccessDesc: String { L10n.string("setup.microphoneAccessDesc") }
        public static var launchAtLogin: String { L10n.string("setup.launchAtLogin") }
        public static var launchAtLoginDesc: String { L10n.string("setup.launchAtLoginDesc") }
        public static var ready: String { L10n.string("setup.ready") }
        public static var download: String { L10n.string("setup.download") }
        public static var downloading: String { L10n.string("setup.downloading") }
        public static var afterFastModel: String { L10n.string("setup.afterFastModel") }
        public static var granted: String { L10n.string("setup.granted") }
        public static var allow: String { L10n.string("setup.allow") }
        public static var enabled: String { L10n.string("setup.enabled") }
        public static var enable: String { L10n.string("setup.enable") }
        public static var optional: String { L10n.string("setup.optional") }
        public static var allSetQualityModel: String { L10n.string("setup.allSetQualityModel") }
        public static var qualityModelDownloading: String { L10n.string("setup.qualityModelDownloading") }
        public static var readyToUse: String { L10n.string("setup.readyToUse") }
        public static func downloadingProgress(_ percent: Int) -> String {
            L10n.string("setup.downloadingProgress", percent)
        }
        public static var modelDownloadRequired: String { L10n.string("setup.modelDownloadRequired") }
        public static var microphoneRequired: String { L10n.string("setup.microphoneRequired") }
    }

    // MARK: - General Settings

    public enum General {
        public static var output: String { L10n.string("general.output") }
        public static var outputDescription: String { L10n.string("general.outputDescription") }
        public static var outputTip: String { L10n.string("general.outputTip") }
        public static var launchAtLogin: String { L10n.string("general.launchAtLogin") }
        public static var showDockIcon: String { L10n.string("general.showDockIcon") }
    }

    // MARK: - Hotkey Settings

    public enum Hotkey {
        public static var transcriptionHotkey: String { L10n.string("hotkey.transcriptionHotkey") }
        public static var toggleRecording: String { L10n.string("hotkey.toggleRecording") }
        public static var hotkeyDescription: String { L10n.string("hotkey.hotkeyDescription") }
        public static var resetToDefault: String { L10n.string("hotkey.resetToDefault") }
        public static var escapeKey: String { L10n.string("hotkey.escapeKey") }
        public static var escapeDescription: String { L10n.string("hotkey.escapeDescription") }
    }

    // MARK: - Audio Settings

    public enum Audio {
        public static var inputDevice: String { L10n.string("audio.inputDevice") }
        public static var microphone: String { L10n.string("audio.microphone") }
        public static var systemDefault: String { L10n.string("audio.systemDefault") }
        public static var inputDeviceDescription: String { L10n.string("audio.inputDeviceDescription") }
        public static var testMicrophone: String { L10n.string("audio.testMicrophone") }
        public static var testInput: String { L10n.string("audio.testInput") }
        public static var testing: String { L10n.string("audio.testing") }
        public static var testDescription: String { L10n.string("audio.testDescription") }
    }

    // MARK: - Model Settings

    public enum Model {
        public static var selectedModel: String { L10n.string("model.selectedModel") }
        public static var modelLabel: String { L10n.string("model.modelLabel") }
        public static var availableModels: String { L10n.string("model.availableModels") }
        public static var performance: String { L10n.string("model.performance") }
        public static var performanceDescription: String { L10n.string("model.performanceDescription") }
        public static var recommended: String { L10n.string("model.recommended") }
        public static var download: String { L10n.string("model.download") }
        public static var delete: String { L10n.string("model.delete") }
        public static var failedToDelete: String { L10n.string("model.failedToDelete") }
        public static var ok: String { L10n.string("model.ok") }
        public static var unknownError: String { L10n.string("model.unknownError") }
    }

    // MARK: - Voice Commands

    public enum VoiceCommands {
        public static var enable: String { L10n.string("voiceCommands.enable") }
        public static var description: String { L10n.string("voiceCommands.description") }
        public static var commands: String { L10n.string("voiceCommands.commands") }
        public static var addCustomCommand: String { L10n.string("voiceCommands.addCustomCommand") }
        public static var resetToDefaults: String { L10n.string("voiceCommands.resetToDefaults") }
        public static var phrase: String { L10n.string("voiceCommands.phrase") }
        public static var newLine: String { L10n.string("voiceCommands.newLine") }
        public static var newParagraph: String { L10n.string("voiceCommands.newParagraph") }
        public static var scratchThat: String { L10n.string("voiceCommands.scratchThat") }
        public static func customText(_ text: String) -> String { L10n.string("voiceCommands.customText", text) }
        public static var addVoiceCommand: String { L10n.string("voiceCommands.addVoiceCommand") }
        public static var triggerPhrase: String { L10n.string("voiceCommands.triggerPhrase") }
        public static var action: String { L10n.string("voiceCommands.action") }
        public static var actionNewLine: String { L10n.string("voiceCommands.actionNewLine") }
        public static var actionNewParagraph: String { L10n.string("voiceCommands.actionNewParagraph") }
        public static var actionCustomText: String { L10n.string("voiceCommands.actionCustomText") }
        public static var customTextLabel: String { L10n.string("voiceCommands.customTextLabel") }
        public static var cancel: String { L10n.string("voiceCommands.cancel") }
        public static var add: String { L10n.string("voiceCommands.add") }
    }

    // MARK: - Advanced Settings

    public enum Advanced {
        public static var autoInsert: String { L10n.string("advanced.autoInsert") }
        public static var autoInsertToggle: String { L10n.string("advanced.autoInsertToggle") }
        public static var autoInsertEnabledDesc: String { L10n.string("advanced.autoInsertEnabledDesc") }
        public static var autoInsertDisabledDesc: String { L10n.string("advanced.autoInsertDisabledDesc") }
        public static var restoreClipboard: String { L10n.string("advanced.restoreClipboard") }
        public static var restoreClipboardDesc: String { L10n.string("advanced.restoreClipboardDesc") }
        public static var accessibilityPermission: String { L10n.string("advanced.accessibilityPermission") }
        public static var accessibilityGranted: String { L10n.string("advanced.accessibilityGranted") }
        public static var openSettings: String { L10n.string("advanced.openSettings") }
        public static var accessibilityRequired: String { L10n.string("advanced.accessibilityRequired") }
        public static var debugging: String { L10n.string("advanced.debugging") }
        public static var enableDetailedLogging: String { L10n.string("advanced.enableDetailedLogging") }
        public static var loggingDescription: String { L10n.string("advanced.loggingDescription") }
        public static var data: String { L10n.string("advanced.data") }
        public static var clearAllData: String { L10n.string("advanced.clearAllData") }
        public static var clearDataDescription: String { L10n.string("advanced.clearDataDescription") }
        public static var failedToClear: String { L10n.string("advanced.failedToClear") }
        public static var about: String { L10n.string("advanced.about") }
        public static var version: String { L10n.string("advanced.version") }
        public static var build: String { L10n.string("advanced.build") }
        public static var distribution: String { L10n.string("advanced.distribution") }
        public static var directInstall: String { L10n.string("advanced.directInstall") }
        public static var appStore: String { L10n.string("advanced.appStore") }
        public static var checkForUpdates: String { L10n.string("advanced.checkForUpdates") }
        public static var updatesDeliveredFrom: String { L10n.string("advanced.updatesDeliveredFrom") }
    }

    // MARK: - Model Download Window

    public enum Download {
        public static var whisperModels: String { L10n.string("download.whisperModels") }
        public static var description: String { L10n.string("download.description") }
        public static var done: String { L10n.string("download.done") }
    }

    // MARK: - Overlay

    public enum Overlay {
        public static var cancelHelp: String { L10n.string("overlay.cancelHelp") }
    }

    // MARK: - Common

    public enum Common {
        public static var ok: String { L10n.string("common.ok") }
        public static var cancel: String { L10n.string("common.cancel") }
        public static var error: String { L10n.string("common.error") }
    }
}
