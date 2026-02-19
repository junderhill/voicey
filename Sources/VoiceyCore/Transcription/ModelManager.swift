import Combine
import Foundation
import WhisperKit
import os

/// Available Whisper model variants
public enum WhisperModel: String, CaseIterable, Identifiable, Hashable {
  case largeTurbo = "large-v3_turbo"
  case large = "large-v3"
  case distilLarge = "distil-large-v3"
  case small = "small"
  case base = "base"
  case tiny = "tiny"
  case smallEn = "small.en"
  case baseEn = "base.en"
  case tinyEn = "tiny.en"

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .largeTurbo: return "Large v3 Turbo"
    case .large: return "Large v3"
    case .distilLarge: return "Distil Large v3"
    case .small: return "Small (Multilingual)"
    case .base: return "Base (Multilingual)"
    case .tiny: return "Tiny (Multilingual)"
    case .smallEn: return "Small (English)"
    case .baseEn: return "Base (English)"
    case .tinyEn: return "Tiny (English)"
    }
  }

  public var description: String {
    switch self {
    case .largeTurbo: return "Fast & accurate, 8x faster than Large (~1.5GB)"
    case .large: return "Maximum accuracy, slower (~3GB)"
    case .distilLarge: return "Distilled model, fast & accurate (~800MB)"
    case .small: return "Balanced speed/accuracy, multilingual (~250MB)"
    case .base: return "Fast, basic accuracy, multilingual (~80MB)"
    case .tiny: return "Fastest, lowest accuracy, multilingual (~40MB)"
    case .smallEn: return "Balanced speed/accuracy, English only (~250MB)"
    case .baseEn: return "Fast, basic accuracy, English only (~80MB)"
    case .tinyEn: return "Fastest, lowest accuracy, English only (~40MB)"
    }
  }

  public var isRecommended: Bool {
    self == .largeTurbo
  }

  public var isEnglishOnly: Bool {
    switch self {
    case .smallEn, .baseEn, .tinyEn: return true
    default: return false
    }
  }

  public var isFastModel: Bool {
    switch self {
    case .base, .baseEn, .tiny, .tinyEn, .small, .smallEn: return true
    default: return false
    }
  }

  public var diskSize: Int64 {
    switch self {
    case .largeTurbo: return 1_500_000_000
    case .large: return 3_000_000_000
    case .distilLarge: return 800_000_000
    case .small, .smallEn: return 250_000_000
    case .base, .baseEn: return 80_000_000
    case .tiny, .tinyEn: return 40_000_000
    }
  }

  public var memoryUsage: Int64 {
    switch self {
    case .largeTurbo: return 3_000_000_000
    case .large: return 6_000_000_000
    case .distilLarge: return 2_000_000_000
    case .small, .smallEn: return 600_000_000
    case .base, .baseEn: return 200_000_000
    case .tiny, .tinyEn: return 100_000_000
    }
  }

  public var whisperKitModelId: String {
    switch self {
    case .largeTurbo: return "openai_whisper-large-v3_turbo"
    case .large: return "openai_whisper-large-v3"
    case .distilLarge: return "distil-whisper_distil-large-v3"
    case .small: return "openai_whisper-small"
    case .base: return "openai_whisper-base"
    case .tiny: return "openai_whisper-tiny"
    case .smallEn: return "openai_whisper-small.en"
    case .baseEn: return "openai_whisper-base.en"
    case .tinyEn: return "openai_whisper-tiny.en"
    }
  }

  /// Whether this model is suitable for use in a keyboard extension (~120MB memory limit)
  public var isSuitableForExtension: Bool {
    memoryUsage <= 250_000_000
  }

  /// Models recommended for keyboard extension use (small memory footprint)
  public static var extensionCompatible: [WhisperModel] {
    allCases.filter { $0.isSuitableForExtension }
  }
}

public typealias ModelUpgradeCallback = (WhisperModel) -> Void

/// Manages downloading, storing, and selecting Whisper models via WhisperKit
public final class ModelManager: ObservableObject {
  public static let shared = ModelManager()

  @Published public var downloadProgress: [WhisperModel: Double] = [:]
  @Published public var downloadedModels: Set<WhisperModel> = []
  @Published public var isDownloading: [WhisperModel: Bool] = [:]
  @Published public var downloadError: String?
  @Published public var isPrewarming: [WhisperModel: Bool] = [:]
  @Published public var pendingUpgradeModel: WhisperModel?

  public var onUpgradeReady: ModelUpgradeCallback?

  /// Notification callbacks -- wired up by the platform layer (macOS app, iOS app)
  public var onDownloadComplete: ((WhisperModel) -> Void)?
  public var onDownloadFailed: ((String) -> Void)?

  private let fileManager = FileManager.default
  private var downloadTasks: [WhisperModel: Task<Void, Never>] = [:]

  private init() {
    loadDownloadedModels()
  }

  // MARK: - Model Hierarchy

  public static let fastModelEnglish = WhisperModel.baseEn
  public static let fastModelMultilingual = WhisperModel.base
  public static let qualityModel = WhisperModel.largeTurbo

  public static var fastModelForCurrentLocale: WhisperModel {
    let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
    if languageCode == "en" {
      return fastModelEnglish
    } else {
      return fastModelMultilingual
    }
  }

  public static var fastModel: WhisperModel {
    fastModelForCurrentLocale
  }

  public var shouldUpgradeToQuality: Bool {
    let currentModel = SettingsManager.shared.selectedModel
    return currentModel.isFastModel && isDownloaded(Self.qualityModel)
  }

  // MARK: - CoreML Compilation Check

  public func isLikelyCompiled(_ model: WhisperModel) -> Bool {
    guard let modelPath = modelPath(for: model) else { return false }
    let modelURL = URL(fileURLWithPath: modelPath)

    let audioEncoderCompiled = modelURL
      .appendingPathComponent("AudioEncoder.mlmodelc/coremldata.bin")

    if fileManager.fileExists(atPath: audioEncoderCompiled.path) {
      if let attrs = try? fileManager.attributesOfItem(atPath: audioEncoderCompiled.path),
         let size = attrs[.size] as? Int64,
         size > 1_000_000 {
        return true
      }
    }

    return false
  }

  // MARK: - Paths

  public var modelsDirectory: URL {
    #if os(iOS)
    // On iOS, use App Group shared container so both host app and keyboard extension can access models
    if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.work.voicey.Voicey") {
      let voiceyDir = containerURL.appendingPathComponent("Models", isDirectory: true)
      if !fileManager.fileExists(atPath: voiceyDir.path) {
        try? fileManager.createDirectory(at: voiceyDir, withIntermediateDirectories: true)
      }
      return voiceyDir
    }
    #endif

    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let voiceyDir = appSupport.appendingPathComponent("Voicey/Models", isDirectory: true)

    if !fileManager.fileExists(atPath: voiceyDir.path) {
      try? fileManager.createDirectory(at: voiceyDir, withIntermediateDirectories: true)
    }

    return voiceyDir
  }

  public func modelPath(for model: WhisperModel) -> String? {
    let whisperKitPath =
      modelsDirectory
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
      .appendingPathComponent(model.whisperKitModelId)

    if isModelComplete(at: whisperKitPath) {
      return whisperKitPath.path
    }

    return nil
  }

  private func isModelComplete(at modelDir: URL) -> Bool {
    let configPath = modelDir.appendingPathComponent("config.json")
    guard fileManager.fileExists(atPath: configPath.path) else {
      return false
    }

    let essentialComponents = [
      "MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"
    ]

    for component in essentialComponents {
      let componentPath = modelDir.appendingPathComponent(component)

      var isDir: ObjCBool = false
      guard fileManager.fileExists(atPath: componentPath.path, isDirectory: &isDir), isDir.boolValue
      else {
        AppLogger.model.warning("Model incomplete: missing \(component)")
        return false
      }

      let coremlDataPath = componentPath.appendingPathComponent("coremldata.bin")
      let weightsPath = componentPath.appendingPathComponent("weights/weight.bin")

      let hasCoremlData = fileManager.fileExists(atPath: coremlDataPath.path)
      let hasWeights = fileManager.fileExists(atPath: weightsPath.path)

      let modelMilPath = componentPath.appendingPathComponent("model.mil")
      let hasModelMil = fileManager.fileExists(atPath: modelMilPath.path)

      if !hasCoremlData && !hasWeights && !hasModelMil {
        AppLogger.model.warning("Model incomplete: \(component) missing essential files")
        return false
      }
    }

    return true
  }

  public var hasDownloadedModel: Bool {
    !downloadedModels.isEmpty
  }

  // MARK: - Model Discovery

  public func loadDownloadedModels() {
    downloadedModels.removeAll()

    for model in WhisperModel.allCases {
      if modelPath(for: model) != nil {
        downloadedModels.insert(model)
      }
    }
  }

  public func isDownloaded(_ model: WhisperModel) -> Bool {
    return modelPath(for: model) != nil
  }

  public func modelFileSize(_ model: WhisperModel) -> Int64? {
    guard let path = modelPath(for: model) else { return nil }
    return directorySize(at: URL(fileURLWithPath: path))
  }

  private func directorySize(at url: URL) -> Int64 {
    var size: Int64 = 0
    let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
    while let fileURL = enumerator?.nextObject() as? URL {
      if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        size += Int64(fileSize)
      }
    }
    return size
  }

  // MARK: - Download

  public func downloadModel(_ model: WhisperModel) {
    guard !isDownloading[model, default: false] else { return }

    isDownloading[model] = true
    downloadProgress[model] = 0
    downloadError = nil

    AppLogger.model.info("Starting download of model: \(model.displayName)")

    cleanupIncompleteDownload(model)

    let task = Task { @MainActor in
      do {
        AppLogger.model.info("Starting WhisperKit download with progress tracking...")

        let modelFolder = try await WhisperKit.download(
          variant: model.rawValue,
          downloadBase: modelsDirectory,
          useBackgroundSession: false,
          progressCallback: { [weak self] progress in
            Task { @MainActor in
              let fraction = progress.fractionCompleted
              self?.downloadProgress[model] = fraction
              AppLogger.model.debug("Download progress: \(Int(fraction * 100))%")
            }
          }
        )

        AppLogger.model.info("Download completed to: \(modelFolder.path)")

        if modelPath(for: model) != nil {
          AppLogger.model.info("Model \(model.displayName) downloaded and verified successfully")
          loadDownloadedModels()
          downloadProgress[model] = 1.0
          isDownloading[model] = false
          downloadTasks[model] = nil
          onDownloadComplete?(model)
        } else {
          AppLogger.model.error(
            "Model download completed but verification failed - files may be incomplete")
          throw ModelDownloadError.verificationFailed
        }
      } catch {
        if !Task.isCancelled {
          let errorMessage = Self.classifyDownloadError(error)
          AppLogger.model.error("Model download failed: \(errorMessage) (underlying: \(error))")
          downloadError = errorMessage
          onDownloadFailed?(errorMessage)
        }
        isDownloading[model] = false
        downloadProgress[model] = 0
        downloadTasks[model] = nil
      }
    }

    downloadTasks[model] = task
  }

  private static func classifyDownloadError(_ error: Error) -> String {
    let errorString = error.localizedDescription.lowercased()
    let nsError = error as NSError

    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet:
        return "No internet connection. Please check your network and try again."
      case NSURLErrorTimedOut:
        return "Download timed out. Please check your network connection and try again."
      case NSURLErrorNetworkConnectionLost:
        return "Network connection was lost. Please try again."
      case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
        return "Cannot reach the model server. Please check your internet connection."
      case NSURLErrorSecureConnectionFailed:
        return "Secure connection failed. Please try again later."
      default:
        return "Network error: \(error.localizedDescription)"
      }
    }

    if errorString.contains("network") || errorString.contains("internet")
      || errorString.contains("connection") {
      return "Network error: Please check your internet connection and try again."
    }

    if errorString.contains("disk") || errorString.contains("space")
      || errorString.contains("storage") {
      return "Insufficient disk space. Please free up some storage and try again."
    }

    if errorString.contains("permission") || errorString.contains("access") {
      return "Permission denied. Please check app permissions."
    }

    if error is ModelDownloadError {
      return "Download incomplete. Please try again."
    }

    return "Download failed: \(error.localizedDescription)"
  }

  public enum ModelDownloadError: LocalizedError {
    case verificationFailed
    case networkUnavailable

    public var errorDescription: String? {
      switch self {
      case .verificationFailed:
        return "Model download verification failed"
      case .networkUnavailable:
        return "Network is unavailable"
      }
    }
  }

  public func cancelDownload(_ model: WhisperModel) {
    downloadTasks[model]?.cancel()
    downloadTasks[model] = nil
    isDownloading[model] = false
    downloadProgress[model] = 0
  }

  public func cleanupIncompleteDownload(_ model: WhisperModel) {
    let whisperKitPath =
      modelsDirectory
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
      .appendingPathComponent(model.whisperKitModelId)

    let cachePath =
      modelsDirectory
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml/.cache/huggingface/download")
      .appendingPathComponent(model.whisperKitModelId)

    if fileManager.fileExists(atPath: whisperKitPath.path) && !isModelComplete(at: whisperKitPath) {
      AppLogger.model.info("Cleaning up incomplete model at \(whisperKitPath.path)")
      try? fileManager.removeItem(at: whisperKitPath)
    }

    if fileManager.fileExists(atPath: cachePath.path) {
      AppLogger.model.info("Cleaning up download cache at \(cachePath.path)")
      try? fileManager.removeItem(at: cachePath)
    }
  }

  // MARK: - Delete

  public func deleteModel(_ model: WhisperModel) throws {
    let whisperKitPath =
      modelsDirectory
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
      .appendingPathComponent(model.whisperKitModelId)

    if fileManager.fileExists(atPath: whisperKitPath.path) {
      try fileManager.removeItem(at: whisperKitPath)
    }

    let directPath = modelsDirectory.appendingPathComponent(model.whisperKitModelId)
    if fileManager.fileExists(atPath: directPath.path) {
      try fileManager.removeItem(at: directPath)
    }

    downloadedModels.remove(model)
    downloadProgress[model] = 0
  }

  // MARK: - Background Upgrade

  public func startBackgroundUpgrade(engine: WhisperEngine) {
    guard !isDownloaded(Self.qualityModel) else {
      Task {
        await prewarmForUpgrade(model: Self.qualityModel, engine: engine)
      }
      return
    }

    AppLogger.model.info(
      "Starting background download of quality model: \(Self.qualityModel.displayName)")
    downloadModel(Self.qualityModel)

    Task {
      await waitForDownloadAndPrewarm(model: Self.qualityModel, engine: engine)
    }
  }

  private func waitForDownloadAndPrewarm(model: WhisperModel, engine: WhisperEngine) async {
    while isDownloading[model] == true {
      try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    guard isDownloaded(model) else {
      AppLogger.model.error("Background download of \(model.displayName) failed")
      return
    }

    await prewarmForUpgrade(model: model, engine: engine)
  }

  private func prewarmForUpgrade(model: WhisperModel, engine: WhisperEngine) async {
    await MainActor.run {
      isPrewarming[model] = true
    }

    debugPrint("🔥 Prewarming \(model.displayName) for background upgrade...", category: "MODEL")
    debugPrint("⏳ This may take 2-5 minutes for CoreML compilation (happens once per model)", category: "MODEL")
    AppLogger.model.info("Prewarming \(model.displayName) for background upgrade...")

    let prewarmEngine = WhisperEngine()

    let modelName = model.displayName
    let progressTask = Task {
      for tick in 1...20 {
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        if Task.isCancelled { break }
        let elapsed = tick * 30
        await MainActor.run {
          debugPrint("⏳ Still prewarming \(modelName)... (\(elapsed)s elapsed)", category: "MODEL")
        }
      }
    }

    do {
      let startTime = CFAbsoluteTimeGetCurrent()
      try await prewarmEngine.loadModel(variant: model.rawValue)
      let loadTime = CFAbsoluteTimeGetCurrent() - startTime

      progressTask.cancel()

      await MainActor.run {
        isPrewarming[model] = false
        pendingUpgradeModel = model

        debugPrint("✅ \(model.displayName) prewarmed in \(String(format: "%.1f", loadTime))s - ready for upgrade!", category: "MODEL")
        AppLogger.model.info("✅ \(model.displayName) prewarmed and ready for upgrade")

        onUpgradeReady?(model)
      }
    } catch {
      progressTask.cancel()

      await MainActor.run {
        isPrewarming[model] = false
        debugPrint("❌ Failed to prewarm \(model.displayName): \(error)", category: "MODEL")
        AppLogger.model.error("Failed to prewarm \(model.displayName): \(error)")
      }
    }
  }

  public func performUpgrade() {
    guard let upgradeModel = pendingUpgradeModel else { return }

    AppLogger.model.info("Upgrading to \(upgradeModel.displayName)")
    SettingsManager.shared.selectedModel = upgradeModel
    pendingUpgradeModel = nil
  }

  // MARK: - Formatting

  public static func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}
