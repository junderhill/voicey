import UIKit
import SwiftUI
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
      },
      checkFullAccess: { [weak self] in
        self?.hasFullAccess ?? false
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
    viewModel?.checkForDictationResult()
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    viewModel?.updateProxy(textDocumentProxy)
  }
}

// MARK: - ViewModel

@MainActor
final class KeyboardViewModel: ObservableObject {
  enum KeyboardState: Equatable {
    case idle
    case waitingForHostApp
    case recording(startTime: Date)
    case processing
    case done(text: String)
    case failed(message: String)
  }

  @Published var hasFullAccess: Bool = false
  @Published var hasModel: Bool = false
  @Published var statusMessage: String = ""
  @Published var keyboardState: KeyboardState = .idle

  /// Whether the host app didn't respond and we need the fallback Link
  @Published var needsFallbackOpen = false

  private var textDocumentProxy: UITextDocumentProxy
  private let advanceToNextInputMethod: () -> Void
  private let checkFullAccessFromController: () -> Bool
  private let bridge = DictationBridge.shared
  private var pollTimer: Timer?
  private var waitTimeout: Task<Void, Never>?

  init(
    textDocumentProxy: UITextDocumentProxy,
    advanceToNextInputMethod: @escaping () -> Void,
    checkFullAccess: @escaping () -> Bool
  ) {
    self.textDocumentProxy = textDocumentProxy
    self.advanceToNextInputMethod = advanceToNextInputMethod
    self.checkFullAccessFromController = checkFullAccess

    refreshFullAccess()
    checkModelAvailability()
    checkForDictationResult()
  }

  func updateProxy(_ proxy: UITextDocumentProxy) {
    textDocumentProxy = proxy
  }

  func switchKeyboard() {
    advanceToNextInputMethod()
  }

  // MARK: - Access & Model Checks

  func refreshFullAccess() {
    hasFullAccess = checkFullAccessFromController()
    AppLogger.audio.info("KeyboardVM: Full Access = \(self.hasFullAccess, privacy: .public)")
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

  // MARK: - Dictation Control

  func startDictation() {
    refreshFullAccess()
    guard hasFullAccess else {
      statusMessage = "Enable Full Access in Settings > Keyboards > Voicey Dictation."
      return
    }
    guard hasModel else {
      statusMessage = "No model available. Open the Voicey app first."
      return
    }

    needsFallbackOpen = false
    keyboardState = .waitingForHostApp
    statusMessage = "Starting..."

    bridge.postStartSignal()
    startPolling()

    // If the host app doesn't start recording within 3 seconds, show fallback
    waitTimeout = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard let self, case .waitingForHostApp = self.keyboardState else { return }
      AppLogger.audio.info("KeyboardVM: Host app didn't respond, showing fallback")
      self.needsFallbackOpen = true
      self.statusMessage = "Voicey app not running. Tap to open it."
    }

    AppLogger.audio.info("KeyboardVM: Start signal posted, waiting for host app")
  }

  func stopDictation() {
    bridge.postStopSignal()
    keyboardState = .processing
    statusMessage = "Transcribing..."
    AppLogger.audio.info("KeyboardVM: Stop signal posted")
  }

  /// Checks for a completed dictation result from the host app and inserts it.
  func checkForDictationResult() {
    let status = bridge.currentStatus

    switch status {
    case .recording:
      waitTimeout?.cancel()
      needsFallbackOpen = false
      if case .recording = keyboardState {
        // Already in recording state, nothing to update
      } else {
        keyboardState = .recording(startTime: Date())
        statusMessage = "Listening..."
      }

    case .processing:
      keyboardState = .processing
      statusMessage = "Transcribing..."

    case .completed:
      if let text = bridge.consumeResult() {
        textDocumentProxy.insertText(text)
        keyboardState = .done(text: text)
        statusMessage = "Done!"
        AppLogger.audio.info("KeyboardVM: Inserted dictation result (\(text.count, privacy: .public) chars)")
        stopPolling()

        Task {
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          if case .done = self.keyboardState {
            self.keyboardState = .idle
            self.statusMessage = "Ready"
          }
        }
      }

    case .failed:
      let error = bridge.errorMessage ?? "Unknown error"
      keyboardState = .failed(message: error)
      statusMessage = "Failed: \(error)"
      bridge.reset()
      stopPolling()

      Task {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if case .failed = self.keyboardState {
          self.keyboardState = .idle
          self.statusMessage = "Ready"
        }
      }

    case .idle, .requested:
      break
    }
  }

  // MARK: - Polling

  private func startPolling() {
    stopPolling()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.checkForDictationResult()
      }
    }
  }

  private func stopPolling() {
    pollTimer?.invalidate()
    pollTimer = nil
    waitTimeout?.cancel()
    waitTimeout = nil
  }

  // MARK: - Fallback (open host app)

  /// Prepares a fallback dictation request for opening the host app via Link.
  func prepareFallbackDictation() {
    bridge.requestDictation()
    statusMessage = "Opening Voicey app..."
    startPolling()
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
