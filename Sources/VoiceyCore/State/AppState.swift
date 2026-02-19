import Combine
import Foundation

/// Represents the current state of the transcription process
public enum TranscriptionState: Equatable {
  case idle
  case loadingModel
  case recording(startTime: Date)
  case processing
  case completed(text: String)
  case error(message: String)

  // MARK: - Convenience Properties

  public var isRecording: Bool {
    if case .recording = self { return true }
    return false
  }

  public var isProcessing: Bool {
    if case .processing = self { return true }
    return false
  }

  public var isLoadingModel: Bool {
    if case .loadingModel = self { return true }
    return false
  }

  public var isActive: Bool {
    switch self {
    case .loadingModel, .recording, .processing:
      return true
    case .idle, .completed, .error:
      return false
    }
  }

  public var recordingDuration: TimeInterval? {
    if case .recording(let startTime) = self {
      return Date().timeIntervalSince(startTime)
    }
    return nil
  }

  public var displayText: String {
    switch self {
    case .idle:
      return L10n.State.ready
    case .loadingModel:
      return L10n.State.loadingModel
    case .recording:
      return L10n.State.listening
    case .processing:
      return L10n.State.transcribing
    case .completed:
      return L10n.State.done
    case .error(let message):
      return L10n.State.error(message)
    }
  }
}

/// Model readiness status
public enum ModelStatus: Equatable {
  case notDownloaded
  case loading
  case ready
  case failed(String)

  public var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  public var isLoading: Bool {
    if case .loading = self { return true }
    return false
  }

  public var statusText: String {
    switch self {
    case .notDownloaded: return L10n.ModelStatus.noModel
    case .loading: return L10n.ModelStatus.loading
    case .ready: return L10n.ModelStatus.ready
    case .failed(let error): return L10n.ModelStatus.error(error)
    }
  }
}

/// Holds the observable application state
public final class AppState: ObservableObject {
  @Published public var transcriptionState: TranscriptionState = .idle
  @Published public var audioLevel: Float = 0.0
  @Published public var currentModel: WhisperModel = SettingsManager.shared.selectedModel
  @Published public var lastTranscription: String = ""
  @Published public var modelStatus: ModelStatus = .notDownloaded

  public init() {}

  // MARK: - Convenience Accessors

  public var isRecording: Bool {
    transcriptionState.isRecording
  }

  public var isReadyToRecord: Bool {
    modelStatus.isReady
  }
}
