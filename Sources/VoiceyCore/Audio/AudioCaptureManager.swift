import AVFoundation
import Accelerate
import os

public protocol AudioCaptureManagerDelegate: AnyObject {
  func audioCaptureManager(_ manager: AudioCaptureManager, didUpdateLevel level: Float)
}

public final class AudioCaptureManager {
  public weak var delegate: AudioCaptureManagerDelegate?

  /// Describes the most recent capture failure, if any.
  public private(set) var lastError: String?

  private var audioEngine: AVAudioEngine?
  private var inputNode: AVAudioInputNode?
  private var audioBuffer: [Float] = []
  private let bufferQueue = DispatchQueue(label: "com.voicetype.audiobuffer", qos: .userInteractive)

  private let targetSampleRate: Double = 16000.0
  private var converter: AVAudioConverter?

  public init() {}

  #if os(iOS)
  private func activateAudioSession() throws {
    let session = AVAudioSession.sharedInstance()

    // Deactivate first to clear any stale state from a previous attempt
    try? session.setActive(false, options: .notifyOthersOnDeactivation)

    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
    try session.setPreferredSampleRate(16000)
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true, options: [])

    let inputs = session.availableInputs ?? []
    let inputNames = inputs.map { $0.portName }.joined(separator: ", ")
    AppLogger.audio.info("AudioCapture: Audio session activated (category=\(session.category.rawValue, privacy: .public), sampleRate=\(session.sampleRate, privacy: .public), inputs=[\(inputNames, privacy: .public)], ioBuffer=\(session.ioBufferDuration, privacy: .public))")
  }
  #endif

  /// Start capturing audio from the microphone.
  /// Returns `true` if capture started successfully, `false` on failure.
  /// Check `lastError` for the specific failure reason.
  @discardableResult
  public func startCapture() -> Bool {
    lastError = nil
    AppLogger.audio.info("AudioCapture: Starting capture...")
    audioBuffer.removeAll()

    #if os(iOS)
    do {
      try activateAudioSession()
    } catch {
      lastError = "Audio session setup failed: \(error.localizedDescription)"
      AppLogger.audio.error("AudioCapture: \(self.lastError!, privacy: .public)")
      return false
    }
    #endif

    audioEngine = AVAudioEngine()
    guard let audioEngine = audioEngine else {
      lastError = "Failed to create audio engine"
      AppLogger.audio.error("AudioCapture: \(self.lastError!, privacy: .public)")
      return false
    }

    inputNode = audioEngine.inputNode
    guard let inputNode = inputNode else {
      lastError = "Failed to get audio input node"
      AppLogger.audio.error("AudioCapture: \(self.lastError!, privacy: .public)")
      return false
    }

    let hwFormat = inputNode.outputFormat(forBus: 0)
    AppLogger.audio.info("AudioCapture: Hardware format - sampleRate=\(hwFormat.sampleRate, privacy: .public), channels=\(hwFormat.channelCount, privacy: .public)")

    let bufferSize: AVAudioFrameCount = 1024
    inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
      self?.processAudioBuffer(buffer)
    }

    audioEngine.prepare()

    do {
      try audioEngine.start()
      AppLogger.audio.info("AudioCapture: Engine started successfully")
      return true
    } catch {
      AppLogger.audio.error("AudioCapture: First start attempt failed: \(error.localizedDescription, privacy: .public), retrying...")

      // Retry once: tear down, re-activate session, and try again
      inputNode.removeTap(onBus: 0)
      audioEngine.reset()

      #if os(iOS)
      do {
        try activateAudioSession()
      } catch {
        lastError = "Audio session re-activation failed: \(error.localizedDescription)"
        AppLogger.audio.error("AudioCapture: \(self.lastError!, privacy: .public)")
        self.audioEngine = nil
        self.inputNode = nil
        return false
      }
      #endif

      inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
        self?.processAudioBuffer(buffer)
      }
      audioEngine.prepare()

      do {
        try audioEngine.start()
        AppLogger.audio.info("AudioCapture: Engine started successfully on retry")
        return true
      } catch {
        lastError = "Audio engine failed to start: \(error.localizedDescription)"
        AppLogger.audio.error("AudioCapture: \(self.lastError!, privacy: .public)")
        inputNode.removeTap(onBus: 0)
        self.audioEngine = nil
        self.inputNode = nil
        return false
      }
    }
  }

  /// Stop capturing audio and return the recorded samples.
  /// - Parameter deactivateSession: If `false`, the audio session stays active
  ///   (used when a keep-alive will reclaim the session).
  public func stopCapture(deactivateSession: Bool = true) -> [Float]? {
    inputNode?.removeTap(onBus: 0)
    audioEngine?.stop()

    var result: [Float]?
    bufferQueue.sync {
      result = audioBuffer
      audioBuffer = []
    }

    audioEngine = nil
    inputNode = nil
    converter = nil

    #if os(iOS)
    if deactivateSession {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    #endif

    let sampleCount = result?.count ?? 0
    let durationSec = Double(sampleCount) / targetSampleRate
    AppLogger.audio.info(
      "AudioCapture: Stopped. Got \(sampleCount) samples (~\(String(format: "%.1f", durationSec))s of audio)"
    )

    return result
  }

  private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }

    let frameLength = Int(buffer.frameLength)
    let inputFormat = buffer.format

    var samples: [Float]

    let needsConversion = inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount > 1
    if needsConversion {
      if converter == nil || converter?.inputFormat != inputFormat {
        let outputFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: targetSampleRate,
          channels: 1,
          interleaved: false
        )!
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
      }
      samples = convertBuffer(buffer)
    } else {
      samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    let level = calculateRMSLevel(samples)
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      self.delegate?.audioCaptureManager(self, didUpdateLevel: level)
    }

    bufferQueue.async { [weak self] in
      self?.audioBuffer.append(contentsOf: samples)
    }
  }

  private func convertBuffer(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let converter = converter else {
      return averageChannels(buffer)
    }

    let inputFormat = buffer.format
    let outputFormat = converter.outputFormat

    let ratio = outputFormat.sampleRate / inputFormat.sampleRate
    let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

    guard
      let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: outputFrameCount
      )
    else {
      return averageChannels(buffer)
    }

    var error: NSError?
    let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }

    if status == .error || error != nil {
      return averageChannels(buffer)
    }

    guard let channelData = outputBuffer.floatChannelData else {
      return averageChannels(buffer)
    }

    return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
  }

  private func averageChannels(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let channelData = buffer.floatChannelData else { return [] }

    let frameLength = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)

    if channelCount == 1 {
      return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    var result = [Float](repeating: 0, count: frameLength)
    for frame in 0..<frameLength {
      var sum: Float = 0
      for channel in 0..<channelCount {
        sum += channelData[channel][frame]
      }
      result[frame] = sum / Float(channelCount)
    }
    return result
  }

  private func calculateRMSLevel(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }

    var rms: Float = 0
    vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

    let decibels = 20 * log10(max(rms, 0.00001))
    let normalizedLevel = (decibels + 60) / 60
    return max(0, min(1, normalizedLevel))
  }

  // MARK: - Device Selection

  public static func availableInputDevices() -> [AVCaptureDevice] {
    #if os(iOS)
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInMicrophone],
      mediaType: .audio,
      position: .unspecified
    )
    #else
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInMicrophone, .externalUnknown],
      mediaType: .audio,
      position: .unspecified
    )
    #endif
    return discoverySession.devices
  }

  public static var defaultInputDevice: AVCaptureDevice? {
    AVCaptureDevice.default(for: .audio)
  }
}
