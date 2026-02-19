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

        if viewModel.transcriptionState.isRecording, let duration = viewModel.transcriptionState.recordingDuration {
          Text(formatDuration(duration))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.red)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .frame(height: 28)

      // Main content area
      ZStack {
        if viewModel.transcriptionState.isRecording {
          recordingView
        } else if viewModel.transcriptionState.isProcessing || viewModel.transcriptionState.isLoadingModel {
          processingView
        } else if !viewModel.hasModel {
          noModelView
        } else {
          idleView
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 120)

      // Bottom toolbar
      HStack(spacing: 20) {
        // Globe / Next keyboard button
        Button(action: { viewModel.switchKeyboard() }) {
          Image(systemName: "globe")
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 36)
        }

        Spacer()

        // Backspace
        Button(action: { viewModel.deleteBackward() }) {
          Image(systemName: "delete.left")
            .font(.system(size: 18))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 36)
        }

        // Space
        Button(action: { viewModel.insertSpace() }) {
          Text("space")
            .font(.caption)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color(.systemBackground))
            .cornerRadius(6)
        }

        // Return
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
      Button(action: { viewModel.toggleRecording() }) {
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

  private var recordingView: some View {
    VStack(spacing: 12) {
      Button(action: { viewModel.toggleRecording() }) {
        ZStack {
          // Pulsing ring
          Circle()
            .stroke(Color.red.opacity(0.3), lineWidth: 3)
            .frame(width: 72, height: 72)
            .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.3)
            .animation(.easeOut(duration: 0.1), value: viewModel.audioLevel)

          Circle()
            .fill(Color.red)
            .frame(width: 64, height: 64)

          // Stop icon
          RoundedRectangle(cornerRadius: 4)
            .fill(.white)
            .frame(width: 22, height: 22)
        }
      }
      .buttonStyle(.plain)

      WaveformView(level: viewModel.audioLevel)
        .frame(width: 120, height: 24)
    }
  }

  private var processingView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .scaleEffect(1.3)

      Text(viewModel.transcriptionState.isLoadingModel ? "Loading model..." : "Transcribing...")
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

      Text("Open the Voicey app to download a speech model.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
  }

  // MARK: - Helpers

  private func formatDuration(_ duration: TimeInterval) -> String {
    let seconds = Int(duration) % 60
    let minutes = Int(duration) / 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
