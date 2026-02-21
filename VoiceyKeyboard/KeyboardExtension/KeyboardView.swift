import SwiftUI
import VoiceyCore

struct KeyboardView: View {
  @ObservedObject var viewModel: KeyboardViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Status bar
      HStack {
        Text(viewModel.statusMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer()

        if case .recording(let startTime) = viewModel.keyboardState {
          Text(startTime, style: .timer)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.red)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .frame(height: 28)

      // Main content area
      ZStack {
        if !viewModel.hasModel {
          noModelView
        } else if !viewModel.hasFullAccess {
          noAccessView
        } else {
          switch viewModel.keyboardState {
          case .idle, .done, .failed:
            if viewModel.needsFallbackOpen {
              fallbackView
            } else {
              idleView
            }
          case .waitingForHostApp:
            waitingView
          case .recording:
            recordingView
          case .processing:
            processingView
          }
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 120)

      // Bottom toolbar
      HStack(spacing: 20) {
        Button(action: { viewModel.switchKeyboard() }) {
          Image(systemName: "globe")
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 36)
        }

        Spacer()

        Button(action: { viewModel.deleteBackward() }) {
          Image(systemName: "delete.left")
            .font(.system(size: 18))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 36)
        }

        Button(action: { viewModel.insertSpace() }) {
          Text("space")
            .font(.caption)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color(.systemBackground))
            .cornerRadius(6)
        }

        Button(action: { viewModel.insertReturn() }) {
          Image(systemName: "return")
            .font(.system(size: 18))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 36)
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
      .frame(height: 44)
    }
    .background(Color(.secondarySystemBackground))
  }

  // MARK: - Sub-views

  private var idleView: some View {
    VStack(spacing: 12) {
      Button(action: { viewModel.startDictation() }) {
        ZStack {
          Circle()
            .fill(Color.red.opacity(0.15))
            .frame(width: 72, height: 72)

          Image(systemName: "mic.fill")
            .font(.system(size: 28))
            .foregroundStyle(.red)
        }
      }
      .buttonStyle(.plain)

      Text("Tap to dictate")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var waitingView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .scaleEffect(1.3)

      Text("Connecting...")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var recordingView: some View {
    VStack(spacing: 12) {
      Button(action: { viewModel.stopDictation() }) {
        ZStack {
          Circle()
            .fill(Color.red)
            .frame(width: 64, height: 64)

          RoundedRectangle(cornerRadius: 4)
            .fill(.white)
            .frame(width: 22, height: 22)
        }
      }
      .buttonStyle(.plain)

      Text("Tap to stop")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var processingView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .scaleEffect(1.3)

      Text("Transcribing...")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  /// Shown when background signaling failed -- opens the host app as fallback.
  private var fallbackView: some View {
    VStack(spacing: 12) {
      Link(destination: DictationBridge.dictateURL) {
        ZStack {
          Circle()
            .fill(Color.blue.opacity(0.15))
            .frame(width: 72, height: 72)

          Image(systemName: "arrow.up.forward.app")
            .font(.system(size: 28))
            .foregroundStyle(.blue)
        }
      }
      .simultaneousGesture(TapGesture().onEnded {
        viewModel.prepareFallbackDictation()
      })

      Text("Open Voicey app to dictate")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var noModelView: some View {
    VStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 28))
        .foregroundStyle(.orange)

      Text("No Model Available")
        .font(.subheadline.weight(.medium))

      Link("Open Voicey to download a model", destination: DictationBridge.hostAppURL)
        .font(.caption)
    }
  }

  private var noAccessView: some View {
    VStack(spacing: 8) {
      Image(systemName: "lock.shield")
        .font(.system(size: 28))
        .foregroundStyle(.orange)

      Text("Full Access Required")
        .font(.subheadline.weight(.medium))

      Text("Settings > Keyboards > Voicey Dictation > Allow Full Access")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
  }
}
