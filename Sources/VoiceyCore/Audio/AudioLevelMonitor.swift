import AVFoundation
import Accelerate
import Combine

/// Provides real-time audio level monitoring for UI feedback
public final class AudioLevelMonitor: ObservableObject {
  @Published public var level: Float = 0
  @Published public var levelHistory: [Float] = []

  private let historySize = 50
  private var cancellables = Set<AnyCancellable>()

  public init() {
    levelHistory = [Float](repeating: 0, count: historySize)
  }

  public func updateLevel(_ newLevel: Float) {
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      self.level = newLevel

      self.levelHistory.append(newLevel)
      if self.levelHistory.count > self.historySize {
        self.levelHistory.removeFirst()
      }
    }
  }

  public func reset() {
    level = 0
    levelHistory = [Float](repeating: 0, count: historySize)
  }
}

// MARK: - Test Audio Level

/// Thread-safe container for tracking max audio level during mic test
private final class MaxLevelTracker: @unchecked Sendable {
  private var _maxLevel: Float = 0
  private let lock = NSLock()

  var maxLevel: Float {
    lock.lock()
    defer { lock.unlock() }
    return _maxLevel
  }

  func update(with level: Float) {
    lock.lock()
    defer { lock.unlock() }
    _maxLevel = max(_maxLevel, level)
  }
}

extension AudioLevelMonitor {
  public static func testMicrophone(
    duration: TimeInterval = 3.0, onLevel: @escaping (Float) -> Void,
    completion: @escaping (Bool) -> Void
  ) {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true)
    } catch {
      completion(false)
      return
    }
    #endif

    let audioEngine = AVAudioEngine()
    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)

    let tracker = MaxLevelTracker()

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      guard let channelData = buffer.floatChannelData else { return }
      let frameLength = Int(buffer.frameLength)

      var rms: Float = 0
      vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameLength))

      let decibels = 20 * log10(max(rms, 0.00001))
      let normalizedLevel = (decibels + 60) / 60
      let level = max(0, min(1, normalizedLevel))

      tracker.update(with: level)

      Task { @MainActor in
        onLevel(level)
      }
    }

    do {
      try audioEngine.start()
    } catch {
      completion(false)
      return
    }

    Task {
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      await MainActor.run {
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        completion(tracker.maxLevel > 0.1)
      }
    }
  }
}
