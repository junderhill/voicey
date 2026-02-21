import AVFoundation
import VoiceyCore

/// Keeps AVAudioEngine running with a microphone input tap at all times.
///
/// This solves two problems:
/// 1. **Keep-alive**: An active recording session maintains the `audio` background
///    mode assertion, so iOS never suspends the host app.
/// 2. **Instant recording**: "Start recording" just flips a flag to begin accumulating
///    samples. The engine is already running, so there's no need to start a new
///    recording session from the background (which iOS blocks).
///
/// IMPORTANT: `startEngine()` must be called while the app is in the foreground.
/// iOS refuses new recording sessions started from the background.
@MainActor
final class PersistentAudioCapture {
  static let shared = PersistentAudioCapture()

  private var audioEngine: AVAudioEngine?
  private var converter: AVAudioConverter?

  private let bufferQueue = DispatchQueue(label: "voicey.persistent-capture", attributes: .concurrent)
  private var audioBuffer: [Float] = []
  private var _isCapturing = false
  private(set) var isEngineRunning = false

  private let targetSampleRate: Double = 16000

  private init() {}

  // MARK: - Engine Lifecycle

  /// Request mic permission if needed, then start the engine.
  /// Safe to call multiple times; no-ops if already running.
  func startEngine() {
    guard !isEngineRunning else {
      AppLogger.audio.info("PersistentCapture: Engine already running")
      return
    }

    let permission = AVAudioSession.sharedInstance().recordPermission
    switch permission {
    case .granted:
      launchAudioEngine()

    case .undetermined:
      AppLogger.audio.info("PersistentCapture: Requesting mic permission")
      AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
        Task { @MainActor in
          if granted {
            self?.launchAudioEngine()
          } else {
            AppLogger.audio.error("PersistentCapture: User denied mic permission")
          }
        }
      }

    case .denied:
      AppLogger.audio.error("PersistentCapture: Mic permission denied. User must enable in Settings.")

    @unknown default:
      break
    }
  }

  /// Actually configures and starts the AVAudioEngine. Only call when mic is granted.
  private func launchAudioEngine() {
    guard !isEngineRunning else { return }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .mixWithOthers])
      try session.setPreferredSampleRate(targetSampleRate)
      try session.setPreferredIOBufferDuration(0.02)
      try session.setActive(true)

      let engine = AVAudioEngine()
      let input = engine.inputNode

      input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
        self?.handleAudioBuffer(buffer)
      }

      engine.prepare()
      try engine.start()

      audioEngine = engine
      isEngineRunning = true

      setupInterruptionHandling()
      AppLogger.audio.info("PersistentCapture: Engine started successfully")
    } catch {
      AppLogger.audio.error("PersistentCapture: Failed to start: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Capture Control

  /// Begin accumulating audio samples. The engine must already be running.
  func beginCapture() {
    bufferQueue.async(flags: .barrier) {
      self.audioBuffer = []
    }
    _isCapturing = true
    AppLogger.audio.info("PersistentCapture: Capture started")
  }

  /// Stop accumulating and return the captured audio.
  /// The engine keeps running for the next request.
  func endCapture() -> [Float]? {
    _isCapturing = false

    var result: [Float]?
    bufferQueue.sync {
      result = self.audioBuffer
    }
    bufferQueue.async(flags: .barrier) {
      self.audioBuffer = []
    }

    let count = result?.count ?? 0
    let duration = Double(count) / targetSampleRate
    AppLogger.audio.info("PersistentCapture: Ended. \(count, privacy: .public) samples (~\(String(format: "%.1f", duration), privacy: .public)s)")
    return result
  }

  // MARK: - Audio Processing

  private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard _isCapturing else { return }
    guard let channelData = buffer.floatChannelData else { return }

    if converter == nil {
      let inputFormat = buffer.format
      if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
        guard let outputFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: targetSampleRate,
          channels: 1,
          interleaved: false
        ) else { return }
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
      }
    }

    if let converter = converter {
      let ratio = targetSampleRate / buffer.format.sampleRate
      let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
      guard let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: converter.outputFormat,
        frameCapacity: outputFrameCount
      ) else { return }

      var error: NSError?
      var consumed = false
      converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        if consumed {
          outStatus.pointee = .noDataNow
          return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return buffer
      }

      guard error == nil, let convertedData = outputBuffer.floatChannelData else { return }
      let samples = Array(UnsafeBufferPointer(start: convertedData[0], count: Int(outputBuffer.frameLength)))
      bufferQueue.async(flags: .barrier) {
        self.audioBuffer.append(contentsOf: samples)
      }
    } else {
      let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
      bufferQueue.async(flags: .barrier) {
        self.audioBuffer.append(contentsOf: samples)
      }
    }
  }

  // MARK: - Interruption Handling

  private func setupInterruptionHandling() {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        self?.handleInterruption(notification)
      }
    }
  }

  private func handleInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }

    switch type {
    case .began:
      AppLogger.audio.info("PersistentCapture: Audio interruption began (phone call, Siri, etc.)")
      isEngineRunning = false

    case .ended:
      AppLogger.audio.info("PersistentCapture: Audio interruption ended, restarting engine")
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        audioEngine?.prepare()
        try audioEngine?.start()
        isEngineRunning = true
        AppLogger.audio.info("PersistentCapture: Engine restarted after interruption")
      } catch {
        AppLogger.audio.error("PersistentCapture: Failed to restart after interruption: \(error.localizedDescription, privacy: .public)")
      }

    @unknown default:
      break
    }
  }
}
