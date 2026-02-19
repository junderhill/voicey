import UIKit
import SwiftUI
import AVFoundation
import VoiceyCore

final class KeyboardViewController: UIInputViewController {
  private var hostingController: UIHostingController<KeyboardView>?
  private var viewModel: KeyboardViewModel?

  override func viewDidLoad() {
    super.viewDidLoad()

    let vm = KeyboardViewModel(
      textDocumentProxy: textDocumentProxy,
      advanceToNextInputMethod: { [weak self] in
        guard let self else { return }
        self.advanceToNextInputMode()
      }
    )
    viewModel = vm

    let keyboardView = KeyboardView(viewModel: vm)
    let hosting = UIHostingController(rootView: keyboardView)
    hosting.view.translatesAutoresizingMaskIntoConstraints = false
    hosting.view.backgroundColor = UIColor.clear

    addChild(hosting)
    view.addSubview(hosting.view)
    hosting.didMove(toParent: self)

    NSLayoutConstraint.activate([
      hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    hostingController = hosting
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    viewModel?.updateProxy(textDocumentProxy)
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    viewModel?.updateProxy(textDocumentProxy)
  }
}

// MARK: - ViewModel

@MainActor
final class KeyboardViewModel: ObservableObject {
  @Published var transcriptionState: TranscriptionState = .idle
  @Published var audioLevel: Float = 0.0
  @Published var hasFullAccess: Bool = false
  @Published var hasModel: Bool = false
  @Published var statusMessage: String = ""

  private var textDocumentProxy: UITextDocumentProxy
  private let advanceToNextInputMethod: () -> Void
  private var audioCaptureManager: AudioCaptureManager?
  private var whisperEngine: WhisperEngine?
  private var postProcessor: PostProcessor?

  init(textDocumentProxy: UITextDocumentProxy, advanceToNextInputMethod: @escaping () -> Void) {
    self.textDocumentProxy = textDocumentProxy
    self.advanceToNextInputMethod = advanceToNextInputMethod

    checkFullAccess()
    checkModelAvailability()
  }

  func updateProxy(_ proxy: UITextDocumentProxy) {
    textDocumentProxy = proxy
  }

  func switchKeyboard() {
    advanceToNextInputMethod()
  }

  // MARK: - Access & Model Checks

  private func checkFullAccess() {
    hasFullAccess = isOpenAccessGranted()
  }

  private func isOpenAccessGranted() -> Bool {
    // Keyboard extensions can check if they have open access by trying to access the pasteboard
    UIPasteboard.general.hasStrings || UIPasteboard.general.string != nil || true
  }

  private func checkModelAvailability() {
    ModelManager.shared.loadDownloadedModels()
    let extensionModels = ModelManager.shared.downloadedModels.filter { $0.isSuitableForExtension }
    hasModel = !extensionModels.isEmpty

    if hasModel {
      statusMessage = "Ready"
    } else if ModelManager.shared.hasDownloadedModel {
      statusMessage = "Model too large for keyboard. Download a smaller model in the Voicey app."
    } else {
      statusMessage = "Open the Voicey app to download a model."
    }
  }

  // MARK: - Recording

  func toggleRecording() {
    if transcriptionState.isRecording {
      stopRecording()
    } else {
      startRecording()
    }
  }

  private func startRecording() {
    guard hasModel else {
      statusMessage = "No model available. Open the Voicey app first."
      return
    }

    // Check microphone permission
    let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    guard micStatus == .authorized else {
      if micStatus == .notDetermined {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
          Task { @MainActor in
            if granted {
              self?.startRecording()
            } else {
              self?.statusMessage = "Microphone access denied. Enable Full Access in Settings."
            }
          }
        }
      } else {
        statusMessage = "Microphone access required. Enable Full Access in Settings > Voicey."
      }
      return
    }

    // Lazily initialize engine
    if whisperEngine == nil {
      whisperEngine = WhisperEngine()
      postProcessor = PostProcessor()
    }

    // Load model if needed
    if whisperEngine?.isModelLoaded != true {
      transcriptionState = .loadingModel
      statusMessage = "Loading model..."

      Task {
        // Pick the best extension-compatible model
        let extensionModels = ModelManager.shared.downloadedModels.filter { $0.isSuitableForExtension }
        guard let model = extensionModels.first else {
          transcriptionState = .error(message: "No compatible model")
          statusMessage = "No compatible model found."
          return
        }

        do {
          try await whisperEngine?.loadModel(variant: model.rawValue)
          beginRecording()
        } catch {
          transcriptionState = .error(message: error.localizedDescription)
          statusMessage = "Failed to load model."
        }
      }
      return
    }

    beginRecording()
  }

  private func beginRecording() {
    if audioCaptureManager == nil {
      audioCaptureManager = AudioCaptureManager()
    }

    // Set up audio level delegate
    let levelUpdater = AudioLevelUpdater { [weak self] level in
      self?.audioLevel = level
    }
    audioCaptureManager?.delegate = levelUpdater
    self._levelUpdater = levelUpdater

    transcriptionState = .recording(startTime: Date())
    statusMessage = "Listening..."
    audioCaptureManager?.startCapture()
  }

  // Prevent deallocation of the delegate
  private var _levelUpdater: AudioLevelUpdater?

  private func stopRecording() {
    guard let audioBuffer = audioCaptureManager?.stopCapture() else {
      transcriptionState = .idle
      statusMessage = "No audio captured."
      return
    }

    _levelUpdater = nil

    let durationSec = Double(audioBuffer.count) / 16000.0
    if durationSec < 0.5 {
      transcriptionState = .idle
      statusMessage = "Too short. Try again."
      return
    }

    transcriptionState = .processing
    statusMessage = "Transcribing..."

    Task {
      await processTranscription(audioBuffer: audioBuffer)
    }
  }

  private func processTranscription(audioBuffer: [Float]) async {
    do {
      guard let result = try await whisperEngine?.transcribe(audioBuffer: audioBuffer) else {
        transcriptionState = .idle
        statusMessage = "Transcription returned no result."
        return
      }

      let processedText = postProcessor?.process(result) ?? result.text

      if processedText.isEmpty {
        transcriptionState = .idle
        statusMessage = "No speech detected."
        return
      }

      textDocumentProxy.insertText(processedText)
      transcriptionState = .completed(text: processedText)
      statusMessage = "Done!"

      // Reset to idle after a short delay
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      if case .completed = transcriptionState {
        transcriptionState = .idle
        statusMessage = "Ready"
      }
    } catch {
      transcriptionState = .error(message: error.localizedDescription)
      statusMessage = "Error: \(error.localizedDescription)"

      try? await Task.sleep(nanoseconds: 2_000_000_000)
      transcriptionState = .idle
      statusMessage = "Ready"
    }
  }

  // MARK: - Utility Actions

  func deleteBackward() {
    textDocumentProxy.deleteBackward()
  }

  func insertSpace() {
    textDocumentProxy.insertText(" ")
  }

  func insertReturn() {
    textDocumentProxy.insertText("\n")
  }
}

// MARK: - Audio Level Bridge

/// Bridges AudioCaptureManagerDelegate to a closure for the view model
private final class AudioLevelUpdater: AudioCaptureManagerDelegate {
  private let onLevel: (Float) -> Void

  init(onLevel: @escaping (Float) -> Void) {
    self.onLevel = onLevel
  }

  func audioCaptureManager(_ manager: AudioCaptureManager, didUpdateLevel level: Float) {
    onLevel(level)
  }
}
