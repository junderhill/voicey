import AVFoundation
import Accelerate
import os

public protocol AudioCaptureManagerDelegate: AnyObject {
  func audioCaptureManager(_ manager: AudioCaptureManager, didUpdateLevel level: Float)
}

public final class AudioCaptureManager {
  public weak var delegate: AudioCaptureManagerDelegate?

  private var audioEngine: AVAudioEngine?
  private var inputNode: AVAudioInputNode?
  private var audioBuffer: [Float] = []
  private let bufferQueue = DispatchQueue(label: "com.voicetype.audiobuffer", qos: .userInteractive)

  private let targetSampleRate: Double = 16000.0
  private var converter: AVAudioConverter?

  public init() {
    setupAudioSession()
  }

  private func setupAudioSession() {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true)
    } catch {
      AppLogger.audio.error("Failed to configure audio session: \(error)")
    }
    #endif
  }

  public func startCapture() {
    AppLogger.audio.info("AudioCapture: Starting capture...")
    audioBuffer.removeAll()

    #if os(iOS)
    setupAudioSession()
    #endif

    audioEngine = AVAudioEngine()
    guard let audioEngine = audioEngine else {
      AppLogger.audio.error("AudioCapture: Failed to create audio engine")
      return
    }

    inputNode = audioEngine.inputNode
    guard let inputNode = inputNode else {
      AppLogger.audio.error("AudioCapture: Failed to get input node")
      return
    }

    let inputFormat = inputNode.outputFormat(forBus: 0)

    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      return
    }

    if inputFormat.sampleRate != targetSampleRate {
      converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    }

    let bufferSize: AVAudioFrameCount = 1024
    inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
      self?.processAudioBuffer(buffer)
    }

    do {
      try audioEngine.start()
    } catch {
      AppLogger.audio.error("Failed to start audio engine: \(error)")
    }
  }

  public func stopCapture() -> [Float]? {
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
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount > 1 {
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
