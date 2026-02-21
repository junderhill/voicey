import AVFoundation
import UIKit
import VoiceyCore

/// Runs in the host app process to handle dictation requests from the keyboard extension.
/// Uses `PersistentAudioCapture` which keeps the mic tap running at all times,
/// so "start recording" is instant (just a flag flip) and the app never gets suspended.
@MainActor
final class BackgroundDictationService: ObservableObject {
  static let shared = BackgroundDictationService()

  @Published var isActive = false

  private let bridge = DictationBridge.shared
  private let capture = PersistentAudioCapture.shared
  private var whisperEngine: WhisperEngine?
  private var postProcessor: PostProcessor?
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
  private var modelLoadTask: Task<Bool, Never>?

  private init() {}

  /// Register Darwin notification listeners.
  /// Call once at app launch (before the app goes to background).
  func start() {
    bridge.registerHostAppListeners(
      onStart: { [weak self] in
        Task { @MainActor in
          self?.handleStartRequest()
        }
      },
      onStop: { [weak self] in
        Task { @MainActor in
          self?.handleStopRequest()
        }
      }
    )
    AppLogger.general.info("BackgroundDictationService: Listening for keyboard signals")
  }

  /// Pre-load the WhisperKit model so transcription starts instantly.
  /// The returned Task can be awaited by transcription if it fires before preload completes.
  func preloadModel() {
    guard modelLoadTask == nil else { return }

    ModelManager.shared.loadDownloadedModels()
    let models = ModelManager.shared.downloadedModels.filter { $0.isSuitableForExtension }
    guard let model = models.first else {
      AppLogger.model.info("BackgroundDictation: No model downloaded yet")
      return
    }

    if whisperEngine == nil {
      whisperEngine = WhisperEngine()
      postProcessor = PostProcessor()
    }

    guard whisperEngine?.isModelLoaded != true else {
      AppLogger.model.info("BackgroundDictation: Model already loaded")
      return
    }

    let engine = whisperEngine
    modelLoadTask = Task {
      do {
        AppLogger.model.info("BackgroundDictation: Pre-loading model '\(model.rawValue, privacy: .public)'")
        try await engine?.loadModel(variant: model.rawValue)
        AppLogger.model.info("BackgroundDictation: Model pre-loaded successfully")
        return true
      } catch {
        AppLogger.model.error("BackgroundDictation: Pre-load failed: \(error.localizedDescription, privacy: .public)")
        return false
      }
    }
  }

  // MARK: - Start / Stop

  private func handleStartRequest() {
    guard !isActive else {
      AppLogger.audio.info("BackgroundDictation: Already active, ignoring duplicate start")
      return
    }

    guard capture.isEngineRunning else {
      AppLogger.audio.error("BackgroundDictation: Engine not running. User must open the app first.")
      bridge.writeFailed("Voicey mic not active. Open the Voicey app once to enable it.")
      return
    }

    AppLogger.audio.info("BackgroundDictation: Start request received, flipping capture flag")
    isActive = true
    bridge.beginRecording()
    capture.beginCapture()
  }

  private func handleStopRequest() {
    guard isActive else { return }
    AppLogger.audio.info("BackgroundDictation: Stop request received")
    isActive = false
    stopAndTranscribe()
  }

  // MARK: - Transcription

  private func stopAndTranscribe() {
    beginBackgroundTask()

    guard let audioBuffer = capture.endCapture() else {
      AppLogger.audio.error("BackgroundDictation: endCapture returned nil")
      bridge.writeFailed("No audio captured.")
      endBackgroundTask()
      return
    }

    let durationSec = Double(audioBuffer.count) / 16000.0
    AppLogger.audio.info("BackgroundDictation: Captured \(audioBuffer.count, privacy: .public) samples (~\(String(format: "%.1f", durationSec), privacy: .public)s)")

    if durationSec < 0.5 {
      bridge.writeFailed("Recording too short.")
      endBackgroundTask()
      return
    }

    bridge.beginProcessing()

    Task {
      await ensureModelLoaded()
      await transcribe(audioBuffer: audioBuffer)
    }
  }

  /// Ensures the WhisperKit model is loaded, waiting for any in-progress preload first.
  private func ensureModelLoaded() async {
    if whisperEngine == nil {
      whisperEngine = WhisperEngine()
      postProcessor = PostProcessor()
    }

    // If preload is running, wait for it
    if let task = modelLoadTask {
      AppLogger.audio.info("BackgroundDictation: Waiting for model preload to finish...")
      _ = await task.value
    }

    guard whisperEngine?.isModelLoaded != true else { return }

    // Model still not loaded (preload failed or never ran). Load now.
    ModelManager.shared.loadDownloadedModels()
    let models = ModelManager.shared.downloadedModels.filter { $0.isSuitableForExtension }
    guard let model = models.first else {
      AppLogger.audio.error("BackgroundDictation: No model available for transcription")
      return
    }

    do {
      AppLogger.audio.info("BackgroundDictation: Loading model on-demand '\(model.rawValue, privacy: .public)'")
      try await whisperEngine?.loadModel(variant: model.rawValue)
      AppLogger.audio.info("BackgroundDictation: Model loaded on-demand")
    } catch {
      AppLogger.audio.error("BackgroundDictation: On-demand model load failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func transcribe(audioBuffer: [Float]) async {
    guard let engine = whisperEngine, engine.isModelLoaded else {
      bridge.writeFailed("No transcription model available. Download one in the Voicey app.")
      endBackgroundTask()
      return
    }

    AppLogger.audio.info("BackgroundDictation: Starting transcription")

    do {
      let result = try await engine.transcribe(audioBuffer: audioBuffer)
      let processedText = postProcessor?.process(result) ?? result.text
      AppLogger.audio.info("BackgroundDictation: Result: '\(processedText, privacy: .public)'")

      if processedText.isEmpty {
        bridge.writeFailed("No speech detected.")
      } else {
        bridge.writeResult(processedText)
      }
    } catch {
      AppLogger.audio.error("BackgroundDictation: Transcription error: \(error.localizedDescription, privacy: .public)")
      bridge.writeFailed("Transcription error: \(error.localizedDescription)")
    }

    endBackgroundTask()
  }

  // MARK: - Background Task (safety net for transcription CPU time)

  private func beginBackgroundTask() {
    guard backgroundTaskID == .invalid else { return }
    backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "VoiceyTranscription") { [weak self] in
      AppLogger.audio.error("BackgroundDictation: Background task expiring!")
      Task { @MainActor in
        self?.bridge.writeFailed("Transcription timed out.")
        self?.endBackgroundTask()
      }
    }
    AppLogger.audio.info("BackgroundDictation: Background task started (id=\(self.backgroundTaskID.rawValue, privacy: .public))")
  }

  private func endBackgroundTask() {
    guard backgroundTaskID != .invalid else { return }
    AppLogger.audio.info("BackgroundDictation: Ending background task (id=\(self.backgroundTaskID.rawValue, privacy: .public))")
    UIApplication.shared.endBackgroundTask(backgroundTaskID)
    backgroundTaskID = .invalid
  }
}
