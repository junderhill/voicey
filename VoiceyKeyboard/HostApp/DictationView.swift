import SwiftUI
import AVFoundation
import VoiceyCore

/// Shown when the host app is opened via voicey://dictate from the keyboard extension.
/// Handles the full record → transcribe → write-result cycle, then prompts the user
/// to return to their previous app.
struct DictationView: View {
  @StateObject private var viewModel = DictationViewModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      statusIcon
      statusText

      if viewModel.state == .recording {
        WaveformView(level: viewModel.audioLevel)
          .frame(width: 160, height: 32)

        Button(action: { viewModel.stopRecording() }) {
          Label("Stop", systemImage: "stop.fill")
            .font(.headline)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color.red)
            .foregroundStyle(.white)
            .cornerRadius(24)
        }
      }

      if viewModel.state == .done || viewModel.state == .failed {
        Text("Switch back to your app to insert the text.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }

      Spacer()

      if viewModel.state == .done || viewModel.state == .failed {
        Button("Dismiss") {
          viewModel.reset()
        }
        .font(.subheadline)
        .padding(.bottom, 24)
      }
    }
    .padding()
    .onAppear {
      viewModel.beginIfNeeded()
    }
    .onChange(of: scenePhase) { newPhase in
      if newPhase == .active {
        viewModel.beginIfNeeded()
      }
    }
  }

  // MARK: - Sub-views

  @ViewBuilder
  private var statusIcon: some View {
    switch viewModel.state {
    case .loadingModel:
      ProgressView()
        .scaleEffect(1.5)
        .frame(width: 80, height: 80)
    case .recording:
      ZStack {
        Circle()
          .fill(Color.red.opacity(0.15))
          .frame(width: 96, height: 96)
          .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.3)
          .animation(.easeOut(duration: 0.1), value: viewModel.audioLevel)

        Circle()
          .fill(Color.red)
          .frame(width: 80, height: 80)

        Image(systemName: "mic.fill")
          .font(.system(size: 32))
          .foregroundStyle(.white)
      }
    case .processing:
      ProgressView()
        .scaleEffect(1.5)
        .frame(width: 80, height: 80)
    case .done:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64))
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 64))
        .foregroundStyle(.orange)
    case .idle:
      Image(systemName: "mic.circle.fill")
        .font(.system(size: 64))
        .foregroundStyle(.blue)
        .symbolRenderingMode(.hierarchical)
    }
  }

  @ViewBuilder
  private var statusText: some View {
    switch viewModel.state {
    case .idle:
      Text("Ready to dictate")
        .font(.title3.weight(.medium))
    case .loadingModel:
      Text("Loading model...")
        .font(.title3.weight(.medium))
    case .recording:
      VStack(spacing: 4) {
        Text("Listening...")
          .font(.title3.weight(.medium))
        if let start = viewModel.recordingStart {
          Text(start, style: .timer)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    case .processing:
      Text("Transcribing...")
        .font(.title3.weight(.medium))
    case .done:
      VStack(spacing: 4) {
        Text("Done!")
          .font(.title3.weight(.medium))
        if let text = viewModel.resultText {
          Text("\"\(text)\"")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .padding(.horizontal, 24)
        }
      }
    case .failed:
      VStack(spacing: 4) {
        Text("Dictation Failed")
          .font(.title3.weight(.medium))
        if let error = viewModel.errorMessage {
          Text(error)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

// MARK: - ViewModel

@MainActor
final class DictationViewModel: ObservableObject {
  enum State {
    case idle, loadingModel, recording, processing, done, failed
  }

  @Published var state: State = .idle
  @Published var audioLevel: Float = 0.0
  @Published var recordingStart: Date?
  @Published var resultText: String?
  @Published var errorMessage: String?

  private let bridge = DictationBridge.shared
  private var audioCaptureManager: AudioCaptureManager?
  private var whisperEngine: WhisperEngine?
  private var postProcessor: PostProcessor?
  private var levelUpdater: AudioLevelUpdater?
  private var hasStarted = false

  /// Starts the dictation flow if there's a pending request from the keyboard.
  func beginIfNeeded() {
    guard !hasStarted else { return }
    guard bridge.hasPendingRequest() || state == .idle else { return }

    hasStarted = true
    bridge.beginRecording()
    startRecordingFlow()
  }

  private func startRecordingFlow() {
    // Check mic permission first
    let permission = AVAudioSession.sharedInstance().recordPermission
    if permission == .undetermined {
      AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
        Task { @MainActor in
          if granted {
            self?.loadModelAndRecord()
          } else {
            self?.fail("Microphone access was denied. Grant access in Settings > Voicey.")
          }
        }
      }
      return
    }

    if permission == .denied {
      fail("Microphone access is denied. Grant access in Settings > Privacy > Microphone.")
      return
    }

    loadModelAndRecord()
  }

  private func loadModelAndRecord() {
    ModelManager.shared.loadDownloadedModels()
    let extensionModels = ModelManager.shared.downloadedModels.filter { $0.isSuitableForExtension }
    guard let model = extensionModels.first else {
      fail("No speech model available. Download one from the main screen.")
      return
    }

    if whisperEngine == nil {
      whisperEngine = WhisperEngine()
      postProcessor = PostProcessor()
    }

    if whisperEngine?.isModelLoaded != true {
      state = .loadingModel
      Task {
        do {
          try await whisperEngine?.loadModel(variant: model.rawValue)
          beginAudioCapture()
        } catch {
          fail("Failed to load model: \(error.localizedDescription)")
        }
      }
    } else {
      beginAudioCapture()
    }
  }

  private func beginAudioCapture() {
    audioCaptureManager = AudioCaptureManager()

    let updater = AudioLevelUpdater { [weak self] level in
      self?.audioLevel = level
    }
    audioCaptureManager?.delegate = updater
    levelUpdater = updater

    let started = audioCaptureManager?.startCapture() ?? false
    guard started else {
      let reason = audioCaptureManager?.lastError ?? "Unknown error"
      fail("Mic error: \(reason)")
      return
    }

    state = .recording
    recordingStart = Date()
    AppLogger.audio.info("DictationView: Recording started")
  }

  func stopRecording() {
    guard state == .recording else { return }

    guard let audioBuffer = audioCaptureManager?.stopCapture() else {
      fail("No audio captured.")
      return
    }

    levelUpdater = nil

    let durationSec = Double(audioBuffer.count) / 16000.0
    AppLogger.audio.info("DictationView: Captured \(audioBuffer.count, privacy: .public) samples (~\(String(format: "%.1f", durationSec), privacy: .public)s)")

    if durationSec < 0.5 {
      fail("Recording was too short. Try speaking for longer.")
      return
    }

    state = .processing
    bridge.beginProcessing()

    Task {
      await transcribe(audioBuffer: audioBuffer)
    }
  }

  private func transcribe(audioBuffer: [Float]) async {
    do {
      guard let result = try await whisperEngine?.transcribe(audioBuffer: audioBuffer) else {
        fail("Transcription returned no result.")
        return
      }

      let processedText = postProcessor?.process(result) ?? result.text
      AppLogger.audio.info("DictationView: Transcription result: '\(processedText, privacy: .public)'")

      if processedText.isEmpty {
        fail("No speech detected. Try speaking more clearly.")
        return
      }

      bridge.writeResult(processedText)
      resultText = processedText
      state = .done
    } catch {
      fail("Transcription error: \(error.localizedDescription)")
    }
  }

  private func fail(_ message: String) {
    AppLogger.audio.error("DictationView: \(message, privacy: .public)")
    errorMessage = message
    state = .failed
    bridge.writeFailed(message)
    levelUpdater = nil
  }

  func reset() {
    state = .idle
    hasStarted = false
    audioLevel = 0
    recordingStart = nil
    resultText = nil
    errorMessage = nil
    bridge.reset()
  }
}

/// Bridges AudioCaptureManagerDelegate to a closure
private final class AudioLevelUpdater: AudioCaptureManagerDelegate {
  private let onLevel: (Float) -> Void

  init(onLevel: @escaping (Float) -> Void) {
    self.onLevel = onLevel
  }

  func audioCaptureManager(_ manager: AudioCaptureManager, didUpdateLevel level: Float) {
    onLevel(level)
  }
}
