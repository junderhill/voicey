import Foundation

/// Facilitates communication between the keyboard extension and host app via:
/// - App Group UserDefaults for state/data transfer
/// - Darwin notifications for real-time IPC signaling
///
/// Primary flow (background, no app switch):
/// 1. Keyboard extension posts a Darwin "start" notification
/// 2. Host app (running in background) receives it and starts recording
/// 3. Keyboard extension posts a "stop" notification
/// 4. Host app stops, transcribes, writes result to shared UserDefaults
/// 5. Keyboard extension polls and inserts the text
///
/// Fallback flow (when host app isn't running):
/// 1. Keyboard extension opens the host app via voicey://dictate URL scheme
/// 2. Host app records, transcribes, writes result
/// 3. Keyboard extension polls and inserts when it reappears
public final class DictationBridge {
  public static let shared = DictationBridge()

  public static let urlScheme = "voicey"
  public static let dictateHost = "dictate"

  /// The URL the keyboard extension should open to trigger dictation in the host app.
  public static var dictateURL: URL {
    URL(string: "\(urlScheme)://\(dictateHost)")!
  }

  /// The URL to open the host app's main screen (e.g. for model setup).
  public static var hostAppURL: URL {
    URL(string: "\(urlScheme)://")!
  }

  // MARK: - Darwin Notification Names

  private static let startNotification = "work.voicey.dictation.start" as CFString
  private static let stopNotification = "work.voicey.dictation.stop" as CFString

  private let defaults: UserDefaults?
  private static let appGroupID = "group.work.voicey.Voicey"

  private enum Keys {
    static let hasPendingRequest = "dictation.hasPendingRequest"
    static let resultText = "dictation.resultText"
    static let resultTimestamp = "dictation.resultTimestamp"
    static let status = "dictation.status"
    static let errorMessage = "dictation.errorMessage"
    static let stopRequested = "dictation.stopRequested"
  }

  public enum Status: String {
    case idle
    case requested
    case recording
    case processing
    case completed
    case failed
  }

  private var onStartReceived: (() -> Void)?
  private var onStopReceived: (() -> Void)?

  private init() {
    defaults = UserDefaults(suiteName: Self.appGroupID)
    if defaults == nil {
      AppLogger.general.error("DictationBridge: Failed to open App Group UserDefaults '\(Self.appGroupID, privacy: .public)'")
    }
  }

  // MARK: - Darwin Notification IPC

  /// Called by the host app to listen for start/stop signals from the keyboard extension.
  public func registerHostAppListeners(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
    self.onStartReceived = onStart
    self.onStopReceived = onStop

    let center = CFNotificationCenterGetDarwinNotifyCenter()

    CFNotificationCenterAddObserver(
      center,
      Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, name, _, _ in
        guard let observer = observer else { return }
        let bridge = Unmanaged<DictationBridge>.fromOpaque(observer).takeUnretainedValue()
        if name?.rawValue == DictationBridge.startNotification {
          AppLogger.general.info("DictationBridge: Received START notification from keyboard")
          bridge.onStartReceived?()
        }
      },
      Self.startNotification,
      nil,
      .deliverImmediately
    )

    CFNotificationCenterAddObserver(
      center,
      Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, name, _, _ in
        guard let observer = observer else { return }
        let bridge = Unmanaged<DictationBridge>.fromOpaque(observer).takeUnretainedValue()
        if name?.rawValue == DictationBridge.stopNotification {
          AppLogger.general.info("DictationBridge: Received STOP notification from keyboard")
          bridge.onStopReceived?()
        }
      },
      Self.stopNotification,
      nil,
      .deliverImmediately
    )

    AppLogger.general.info("DictationBridge: Host app listeners registered")
  }

  /// Called by the keyboard extension to signal the host app to start recording.
  public func postStartSignal() {
    requestDictation()
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(Self.startNotification),
      nil,
      nil,
      true
    )
    AppLogger.general.info("DictationBridge: Posted START notification")
  }

  /// Called by the keyboard extension to signal the host app to stop recording.
  public func postStopSignal() {
    defaults?.set(true, forKey: Keys.stopRequested)
    defaults?.synchronize()
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(Self.stopNotification),
      nil,
      nil,
      true
    )
    AppLogger.general.info("DictationBridge: Posted STOP notification")
  }

  /// Called by the host app to check if stop was requested.
  public var isStopRequested: Bool {
    defaults?.bool(forKey: Keys.stopRequested) ?? false
  }

  // MARK: - Keyboard Extension Side

  /// Called by the keyboard extension to signal that dictation is requested.
  public func requestDictation() {
    defaults?.set(true, forKey: Keys.hasPendingRequest)
    defaults?.set(Status.requested.rawValue, forKey: Keys.status)
    defaults?.set(false, forKey: Keys.stopRequested)
    defaults?.removeObject(forKey: Keys.resultText)
    defaults?.removeObject(forKey: Keys.errorMessage)
    defaults?.synchronize()
    AppLogger.general.info("DictationBridge: Request flagged")
  }

  /// Called by the keyboard extension to check if a transcription result is available.
  /// Returns the transcribed text if available, then clears it.
  public func consumeResult() -> String? {
    guard let text = defaults?.string(forKey: Keys.resultText),
          !text.isEmpty else {
      return nil
    }

    defaults?.removeObject(forKey: Keys.resultText)
    defaults?.removeObject(forKey: Keys.resultTimestamp)
    defaults?.set(Status.idle.rawValue, forKey: Keys.status)
    defaults?.synchronize()
    AppLogger.general.info("DictationBridge: Result consumed (\(text.count, privacy: .public) chars)")
    return text
  }

  /// Returns the current status (re-reads from disk to get cross-process updates).
  public var currentStatus: Status {
    defaults?.synchronize()
    guard let raw = defaults?.string(forKey: Keys.status),
          let status = Status(rawValue: raw) else {
      return .idle
    }
    return status
  }

  /// Returns the error message if the last dictation failed.
  public var errorMessage: String? {
    defaults?.string(forKey: Keys.errorMessage)
  }

  // MARK: - Host App Side

  /// Called by the host app to check if the keyboard extension has requested dictation.
  public func hasPendingRequest() -> Bool {
    defaults?.bool(forKey: Keys.hasPendingRequest) ?? false
  }

  /// Called by the host app to acknowledge the request and begin recording.
  public func beginRecording() {
    defaults?.set(false, forKey: Keys.hasPendingRequest)
    defaults?.set(false, forKey: Keys.stopRequested)
    defaults?.set(Status.recording.rawValue, forKey: Keys.status)
    defaults?.synchronize()
  }

  /// Called by the host app to signal that transcription is in progress.
  public func beginProcessing() {
    defaults?.set(Status.processing.rawValue, forKey: Keys.status)
    defaults?.synchronize()
  }

  /// Called by the host app to write the transcription result.
  public func writeResult(_ text: String) {
    defaults?.set(text, forKey: Keys.resultText)
    defaults?.set(Date().timeIntervalSince1970, forKey: Keys.resultTimestamp)
    defaults?.set(Status.completed.rawValue, forKey: Keys.status)
    defaults?.synchronize()
    AppLogger.general.info("DictationBridge: Result written (\(text.count, privacy: .public) chars)")
  }

  /// Called by the host app to signal a failure.
  public func writeFailed(_ message: String) {
    defaults?.set(Status.failed.rawValue, forKey: Keys.status)
    defaults?.set(message, forKey: Keys.errorMessage)
    defaults?.synchronize()
    AppLogger.general.error("DictationBridge: Failed - \(message, privacy: .public)")
  }

  /// Resets all dictation state.
  public func reset() {
    defaults?.removeObject(forKey: Keys.hasPendingRequest)
    defaults?.removeObject(forKey: Keys.resultText)
    defaults?.removeObject(forKey: Keys.resultTimestamp)
    defaults?.removeObject(forKey: Keys.errorMessage)
    defaults?.removeObject(forKey: Keys.stopRequested)
    defaults?.set(Status.idle.rawValue, forKey: Keys.status)
    defaults?.synchronize()
  }
}
