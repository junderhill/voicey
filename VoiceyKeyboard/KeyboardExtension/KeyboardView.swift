import SwiftUI
import VoiceyCore

struct KeyboardView: View {
  @ObservedObject var viewModel: KeyboardViewModel

  var body: some View {
    VStack(spacing: 0) {
      statusBar
      mainContent
      bottomToolbar
    }
    .background(
      Color(.secondarySystemBackground)
        .overlay(
          LinearGradient(
            colors: [Color.white.opacity(0.04), Color.clear],
            startPoint: .top,
            endPoint: .bottom
          )
        )
    )
  }

  // MARK: - Status Bar

  private var statusBar: some View {
    HStack(spacing: 6) {
      statusPill

      Spacer()

      if case .recording(let startTime) = viewModel.keyboardState {
        HStack(spacing: 4) {
          Circle()
            .fill(.red)
            .frame(width: 6, height: 6)

          Text(startTime, style: .timer)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.1))
        .clipShape(Capsule())
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }

  private var statusPill: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(statusDotColor)
        .frame(width: 6, height: 6)

      Text(viewModel.statusMessage)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  private var statusDotColor: Color {
    switch viewModel.keyboardState {
    case .idle, .done:
      return .green
    case .recording:
      return .red
    case .processing, .waitingForHostApp:
      return .orange
    case .failed:
      return .red
    }
  }

  // MARK: - Main Content

  private var mainContent: some View {
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
    .frame(height: 110)
    .animation(.easeInOut(duration: 0.25), value: viewModel.keyboardState)
  }

  // MARK: - Bottom Toolbar

  private var bottomToolbar: some View {
    HStack(spacing: 6) {
      toolbarButton(icon: "globe") {
        viewModel.switchKeyboard()
      }

      toolbarButton(icon: "delete.left") {
        viewModel.deleteBackward()
      }

      Button(action: { viewModel.insertSpace() }) {
        Text("space")
          .font(.system(size: 14, weight: .regular))
          .foregroundStyle(Color(.label))
          .frame(maxWidth: .infinity)
          .frame(height: 38)
          .background(Color(.systemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
      }

      toolbarButton(icon: "return") {
        viewModel.insertReturn()
      }
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 4)
    .padding(.top, 2)
  }

  private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(Color(.label))
        .frame(width: 44, height: 38)
        .background(Color(.systemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 0.5, y: 0.5)
    }
  }

  // MARK: - Idle View

  private var idleView: some View {
    VStack(spacing: 10) {
      Button(action: { viewModel.startDictation() }) {
        MicButtonView()
      }
      .buttonStyle(MicButtonStyle())

      Text("Tap to dictate")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.tertiary)
    }
  }

  // MARK: - Recording View

  private var recordingView: some View {
    VStack(spacing: 10) {
      Button(action: { viewModel.stopDictation() }) {
        ZStack {
          WaveformRingsView()

          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white)
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        }
        .frame(width: 68, height: 68)
      }
      .buttonStyle(MicButtonStyle())

      Text("Listening... tap to stop")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Processing View

  private var processingView: some View {
    VStack(spacing: 14) {
      ZStack {
        Circle()
          .stroke(Color.accentColor.opacity(0.15), lineWidth: 3)
          .frame(width: 52, height: 52)

        SpinnerView()
          .frame(width: 52, height: 52)
      }

      Text("Transcribing...")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Waiting View

  private var waitingView: some View {
    VStack(spacing: 14) {
      ZStack {
        Circle()
          .stroke(Color.orange.opacity(0.15), lineWidth: 3)
          .frame(width: 52, height: 52)

        SpinnerView(color: .orange)
          .frame(width: 52, height: 52)
      }

      Text("Connecting to Voicey...")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Fallback View

  private var fallbackView: some View {
    VStack(spacing: 10) {
      Link(destination: DictationBridge.dictateURL) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 68, height: 68)

          Image(systemName: "arrow.up.forward.app.fill")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.blue)
        }
      }
      .simultaneousGesture(TapGesture().onEnded {
        viewModel.prepareFallbackDictation()
      })

      Text("Open Voicey to dictate")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Error Views

  private var noModelView: some View {
    VStack(spacing: 8) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(.orange)

      Text("Model Required")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)

      Link(destination: DictationBridge.hostAppURL) {
        Text("Download in Voicey App")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .background(Color.orange)
          .clipShape(Capsule())
      }
    }
  }

  private var noAccessView: some View {
    VStack(spacing: 8) {
      Image(systemName: "lock.shield")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(.orange)

      Text("Full Access Required")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)

      Text("Settings → Keyboards → Voicey → Full Access")
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
  }
}

// MARK: - Mic Button

private struct MicButtonView: View {
  @State private var isPulsing = false

  var body: some View {
    ZStack {
      Circle()
        .fill(
          RadialGradient(
            colors: [Color.red.opacity(0.18), Color.red.opacity(0.04)],
            center: .center,
            startRadius: 0,
            endRadius: 42
          )
        )
        .frame(width: 72, height: 72)
        .scaleEffect(isPulsing ? 1.06 : 1.0)

      Circle()
        .fill(
          LinearGradient(
            colors: [Color.red.opacity(0.9), Color.red],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: 52, height: 52)
        .shadow(color: .red.opacity(0.3), radius: 8, y: 3)

      Image(systemName: "mic.fill")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.white)
    }
    .onAppear {
      withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
  }
}

private struct MicButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

// MARK: - Waveform Rings (Recording)

private struct WaveformRingsView: View {
  @State private var animate = false

  var body: some View {
    ZStack {
      ForEach(0..<3, id: \.self) { i in
        Circle()
          .stroke(Color.red.opacity(animate ? 0.0 : 0.3), lineWidth: 2)
          .frame(
            width: animate ? 68 : 30,
            height: animate ? 68 : 30
          )
          .animation(
            .easeOut(duration: 1.6)
              .repeatForever(autoreverses: false)
              .delay(Double(i) * 0.5),
            value: animate
          )
      }

      Circle()
        .fill(
          LinearGradient(
            colors: [Color.red.opacity(0.85), Color.red],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: 52, height: 52)
        .shadow(color: .red.opacity(0.35), radius: 10, y: 3)
    }
    .onAppear { animate = true }
  }
}

// MARK: - Spinner (Processing)

private struct SpinnerView: View {
  var color: Color = .accentColor
  @State private var rotating = false

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.7)
      .stroke(
        AngularGradient(
          colors: [color.opacity(0), color],
          center: .center
        ),
        style: StrokeStyle(lineWidth: 3, lineCap: .round)
      )
      .rotationEffect(.degrees(rotating ? 360 : 0))
      .onAppear {
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
          rotating = true
        }
      }
  }
}
