import Foundation
import WhisperKit
import os

/// Result from Whisper transcription including text and timing information
public struct TranscriptionResult {
  public let text: String
  public let segments: [TranscriptionSegment]
  public let language: String
  public let processingTime: TimeInterval
  public let performanceMetrics: PerformanceMetrics

  public init(text: String, segments: [TranscriptionSegment], language: String, processingTime: TimeInterval, performanceMetrics: PerformanceMetrics) {
    self.text = text
    self.segments = segments
    self.language = language
    self.processingTime = processingTime
    self.performanceMetrics = performanceMetrics
  }
}

/// Performance metrics for transcription
public struct PerformanceMetrics {
  public let realTimeFactor: Double
  public let audioDuration: TimeInterval
  public let processingTime: TimeInterval
  public let thermalState: ProcessInfo.ThermalState

  public init(realTimeFactor: Double, audioDuration: TimeInterval, processingTime: TimeInterval, thermalState: ProcessInfo.ThermalState) {
    self.realTimeFactor = realTimeFactor
    self.audioDuration = audioDuration
    self.processingTime = processingTime
    self.thermalState = thermalState
  }

  public var isStruggling: Bool {
    if realTimeFactor > 2.0 { return true }
    if thermalState == .critical { return true }
    if thermalState == .serious && realTimeFactor > 1.0 { return true }
    return false
  }

  public var description: String {
    let rtfStr = String(format: "%.2fx", realTimeFactor)
    let thermalStr: String
    switch thermalState {
    case .nominal: thermalStr = "nominal"
    case .fair: thermalStr = "fair"
    case .serious: thermalStr = "serious"
    case .critical: thermalStr = "critical"
    @unknown default: thermalStr = "unknown"
    }
    return "RTF: \(rtfStr), Thermal: \(thermalStr)"
  }

  public var suggestion: String? {
    if thermalState == .critical || thermalState == .serious {
      return
        "System is running hot. Consider using a smaller model or letting the device cool down."
    }
    if realTimeFactor > 2.0 {
      return
        "Transcription is slow. Consider switching to a faster model like 'Small' for better performance."
    }
    if realTimeFactor > 1.5 {
      return "Transcription may be slow on longer recordings. A smaller model might help."
    }
    return nil
  }
}

public struct TranscriptionSegment {
  public let text: String
  public let startTime: TimeInterval
  public let endTime: TimeInterval
  public let tokens: [TranscriptionToken]

  public init(text: String, startTime: TimeInterval, endTime: TimeInterval, tokens: [TranscriptionToken]) {
    self.text = text
    self.startTime = startTime
    self.endTime = endTime
    self.tokens = tokens
  }
}

public struct TranscriptionToken {
  public let text: String
  public let probability: Float
  public let startTime: TimeInterval
  public let endTime: TimeInterval

  public init(text: String, probability: Float, startTime: TimeInterval, endTime: TimeInterval) {
    self.text = text
    self.probability = probability
    self.startTime = startTime
    self.endTime = endTime
  }
}

/// Wrapper around WhisperKit for on-device speech-to-text
public final class WhisperEngine {
  private var whisperKit: WhisperKit?
  private var isLoading = false
  private var loadedModelVariant: String?

  public var onLoadingStateChanged: ((Bool) -> Void)?
  public var onPerformanceIssue: ((PerformanceMetrics) -> Void)?

  private var recentRTFs: [Double] = []
  private let maxRTFHistory = 5

  public var averageRTF: Double {
    guard !recentRTFs.isEmpty else { return 0 }
    return recentRTFs.reduce(0, +) / Double(recentRTFs.count)
  }

  public var isSystemStruggling: Bool {
    guard recentRTFs.count >= 2 else { return false }
    let avgRTF = averageRTF
    let thermalState = ProcessInfo.processInfo.thermalState

    if avgRTF > 1.5 { return true }
    if thermalState == .critical || thermalState == .serious { return true }
    return false
  }

  public var thermalState: ProcessInfo.ThermalState {
    ProcessInfo.processInfo.thermalState
  }

  public init() {}

  public func preloadModel() async {
    guard !isLoading && whisperKit == nil else { return }

    var modelToLoad = SettingsManager.shared.selectedModel
    debugPrint("🎯 Selected model: \(modelToLoad.rawValue)", category: "MODEL")
    debugPrint(
      "📋 Downloaded models: \(ModelManager.shared.downloadedModels.map { $0.rawValue })",
      category: "MODEL")

    if !ModelManager.shared.isDownloaded(modelToLoad) {
      if let bestAvailable = Self.selectBestAvailableModel(from: ModelManager.shared.downloadedModels) {
        debugPrint("⚠️ Selected model not downloaded, falling back to \(bestAvailable.rawValue)", category: "MODEL")
        modelToLoad = bestAvailable
        SettingsManager.shared.selectedModel = bestAvailable
      } else {
        debugPrint("⚠️ No models downloaded, skipping preload", category: "MODEL")
        return
      }
    } else {
      if !ModelManager.shared.isLikelyCompiled(modelToLoad),
        let bestStartup = Self.selectBestAvailableModel(from: ModelManager.shared.downloadedModels),
        bestStartup != modelToLoad {
        debugPrint(
          "⚠️ Selected model '\(modelToLoad.rawValue)' not compiled yet; preloading '\(bestStartup.rawValue)' first for faster startup",
          category: "MODEL"
        )
        modelToLoad = bestStartup
        SettingsManager.shared.selectedModel = bestStartup
      }
    }

    do {
      try await loadModel(variant: modelToLoad.rawValue)
      debugPrint("✅ Model '\(modelToLoad.rawValue)' preloaded successfully", category: "MODEL")
      AppLogger.model.info("WhisperEngine: Model \(modelToLoad.rawValue) preloaded successfully")
    } catch {
      debugPrint("❌ Model preload failed: \(error)", category: "MODEL")
      AppLogger.model.error("WhisperEngine: Failed to preload model: \(error)")
    }
  }

  private static func selectBestAvailableModel(from models: Set<WhisperModel>) -> WhisperModel? {
    guard !models.isEmpty else { return nil }

    let qualityFirst: [WhisperModel] = [.largeTurbo, .large, .distilLarge, .small, .base, .tiny]
    for model in qualityFirst {
      if models.contains(model) && ModelManager.shared.isLikelyCompiled(model) {
        debugPrint("🚀 Found already-compiled model: \(model.rawValue)", category: "MODEL")
        return model
      }
    }

    let smallFirst: [WhisperModel] = [.tiny, .base, .small, .distilLarge, .large, .largeTurbo]
    for model in smallFirst {
      if models.contains(model) {
        debugPrint("📦 No compiled models found, using fastest to compile: \(model.rawValue)", category: "MODEL")
        return model
      }
    }

    return models.first
  }

  public func loadModel(variant: String = "base.en") async throws {
    if whisperKit != nil && loadedModelVariant == variant {
      AppLogger.model.info("WhisperEngine: Model \(variant) already loaded, skipping")
      return
    }

    guard !isLoading else {
      AppLogger.model.info("WhisperEngine: Already loading a model, skipping")
      return
    }
    isLoading = true

    await MainActor.run {
      onLoadingStateChanged?(true)
    }

    defer {
      isLoading = false
      Task { @MainActor in
        onLoadingStateChanged?(false)
      }
    }

    whisperKit = nil
    loadedModelVariant = nil

    guard let selectedModel = WhisperModel(rawValue: variant) else {
      AppLogger.model.error("WhisperEngine: Unknown model variant '\(variant)'")
      throw WhisperError.failedToLoadModel
    }

    guard let modelPath = ModelManager.shared.modelPath(for: selectedModel) else {
      AppLogger.model.error("WhisperEngine: Model '\(variant)' not found on disk")
      throw WhisperError.noModelLoaded
    }

    debugPrint("📂 Model path: \(modelPath)", category: "MODEL")
    debugPrint(
      "⏳ Loading model '\(variant)' (first run may take 1-3 minutes for CoreML compilation)...",
      category: "MODEL")
    AppLogger.model.info("WhisperEngine: Loading model '\(variant)' from \(modelPath)")

    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let variantName = variant
      let progressTask = Task {
        for tick in 1...20 {
          try? await Task.sleep(nanoseconds: 30_000_000_000)
          if Task.isCancelled { return }
          let elapsed = tick * 30
          let thermal = ProcessInfo.processInfo.thermalState
          let thermalStr: String
          switch thermal {
          case .nominal: thermalStr = "nominal"
          case .fair: thermalStr = "fair"
          case .serious: thermalStr = "serious"
          case .critical: thermalStr = "critical"
          @unknown default: thermalStr = "unknown"
          }
          debugPrint(
            "⏳ Still loading model '\(variantName)'... (\(elapsed)s elapsed, thermal: \(thermalStr))",
            category: "MODEL"
          )
          if elapsed == 180 {
            debugPrint(
              "💡 First-time CoreML compilation can take several minutes even for smaller models. Subsequent launches should be much faster.",
              category: "MODEL"
            )
          }
        }
      }
      defer { progressTask.cancel() }

      let config = WhisperKitConfig(
        model: variant,
        modelFolder: modelPath,
        download: false,
        useBackgroundDownloadSession: false
      )

      whisperKit = try await WhisperKit(config)
    } catch {
      debugPrint("❌ Failed to load model: \(error)", category: "MODEL")
      AppLogger.model.error("WhisperEngine: Failed to load model '\(variant)': \(error)")
      AppLogger.model.error("WhisperEngine: Error details: \(String(describing: error))")
      throw error
    }

    loadedModelVariant = variant
    let loadTime = CFAbsoluteTimeGetCurrent() - startTime
    debugPrint("✅ Model loaded in \(String(format: "%.1f", loadTime))s", category: "MODEL")
    AppLogger.model.info("WhisperEngine: Model loaded in \(String(format: "%.2f", loadTime))s")
  }

  public func unloadModel() {
    whisperKit = nil
    loadedModelVariant = nil
  }

  public var isModelLoaded: Bool {
    whisperKit != nil
  }

  public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
    if whisperKit == nil {
      let selectedModel = SettingsManager.shared.selectedModel
      debugPrint("🔄 Loading model for transcription: \(selectedModel.rawValue)", category: "MODEL")

      guard ModelManager.shared.isDownloaded(selectedModel) else {
        debugPrint("❌ Model '\(selectedModel.rawValue)' not downloaded!", category: "MODEL")
        throw WhisperError.noModelLoaded
      }

      try await loadModel(variant: selectedModel.rawValue)
    }

    guard let whisperKit = whisperKit else {
      throw WhisperError.noModelLoaded
    }

    let audioDuration = Double(audioBuffer.count) / 16000.0
    let thermalStateBefore = ProcessInfo.processInfo.thermalState

    AppLogger.transcription.info(
      "WhisperEngine: Starting transcription of \(audioBuffer.count) samples (~\(String(format: "%.1f", audioDuration))s)..."
    )
    let startTime = CFAbsoluteTimeGetCurrent()

    let options = DecodingOptions(
      verbose: SettingsManager.shared.enableDetailedLogging,
      task: .transcribe,
      language: "en",
      temperatureFallbackCount: 1,
      sampleLength: 224,
      usePrefillPrompt: true,
      usePrefillCache: true,
      skipSpecialTokens: true,
      withoutTimestamps: false,
      wordTimestamps: false
    )

    AppLogger.transcription.info(
      "WhisperEngine: Calling whisperKit.transcribe() with \(audioBuffer.count) samples...")

    let results = try await whisperKit.transcribe(
      audioArray: audioBuffer,
      decodeOptions: options
    )

    let processingTime = CFAbsoluteTimeGetCurrent() - startTime

    let rtf = audioDuration > 0 ? processingTime / audioDuration : 0
    let metrics = PerformanceMetrics(
      realTimeFactor: rtf,
      audioDuration: audioDuration,
      processingTime: processingTime,
      thermalState: thermalStateBefore
    )

    recentRTFs.append(rtf)
    if recentRTFs.count > maxRTFHistory {
      recentRTFs.removeFirst()
    }

    AppLogger.transcription.info(
      "WhisperEngine: Transcription completed in \(String(format: "%.2f", processingTime))s (RTF: \(String(format: "%.2f", rtf)))"
    )

    debugPrint("📊 Performance: \(metrics.description)", category: "PERF")
    if let suggestion = metrics.suggestion {
      debugPrint("💡 \(suggestion)", category: "PERF")
    }

    if metrics.isStruggling {
      AppLogger.transcription.warning(
        "WhisperEngine: System appears to be struggling with transcription")
      await MainActor.run {
        onPerformanceIssue?(metrics)
      }
    }

    AppLogger.transcription.info("WhisperEngine: Got \(results.count) result(s)")

    guard let result = results.first else {
      AppLogger.transcription.error("WhisperEngine: No results returned from transcription")
      throw WhisperError.transcriptionFailed
    }

    AppLogger.transcription.info("WhisperEngine: Raw text: \"\(result.text)\"")
    AppLogger.transcription.info(
      "WhisperEngine: Segments: \(result.segments.count), Language: \(result.language)")

    var segments: [TranscriptionSegment] = []

    for segment in result.segments {
      var tokens: [TranscriptionToken] = []

      for word in segment.words ?? [] {
        tokens.append(
          TranscriptionToken(
            text: word.word,
            probability: word.probability,
            startTime: TimeInterval(word.start),
            endTime: TimeInterval(word.end)
          ))
      }

      segments.append(
        TranscriptionSegment(
          text: segment.text,
          startTime: TimeInterval(segment.start),
          endTime: TimeInterval(segment.end),
          tokens: tokens
        ))
    }

    let fullText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    AppLogger.transcription.info("WhisperEngine: Result: \"\(fullText)\"")

    return TranscriptionResult(
      text: fullText,
      segments: segments,
      language: result.language,
      processingTime: processingTime,
      performanceMetrics: metrics
    )
  }

  public func checkSystemPerformance() -> (
    thermalState: ProcessInfo.ThermalState, avgRTF: Double, isStruggling: Bool
  ) {
    return (thermalState, averageRTF, isSystemStruggling)
  }

  public func resetPerformanceTracking() {
    recentRTFs.removeAll()
  }
}

// MARK: - Errors

public enum WhisperError: LocalizedError {
  case failedToLoadModel
  case noModelLoaded
  case transcriptionFailed

  public var errorDescription: String? {
    switch self {
    case .failedToLoadModel:
      return "Failed to load the Whisper model"
    case .noModelLoaded:
      return "No transcription model is loaded"
    case .transcriptionFailed:
      return "Transcription failed"
    }
  }
}
