import SwiftUI
import VoiceyCore

struct ContentView: View {
  @StateObject private var modelManager = ModelManager.shared
  @State private var selectedTab = 0

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          headerSection
          keyboardSetupSection
          modelSection
        }
        .padding()
      }
      .navigationTitle("Voicey")
    }
  }

  // MARK: - Header

  private var headerSection: some View {
    VStack(spacing: 12) {
      Image(systemName: "mic.badge.waveform")
        .font(.system(size: 48))
        .foregroundStyle(.blue)
        .symbolRenderingMode(.hierarchical)

      Text("Voice-to-Text Keyboard")
        .font(.title2.weight(.semibold))

      Text("Dictate text in any app using on-device AI. No cloud, no data leaves your device.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 8)
  }

  // MARK: - Keyboard Setup Instructions

  private var keyboardSetupSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Keyboard Setup", systemImage: "keyboard")
        .font(.headline)

      SetupStepView(
        number: 1,
        title: "Open Settings",
        description: "Go to Settings > General > Keyboard > Keyboards",
        actionLabel: "Open Settings",
        action: openKeyboardSettings
      )

      SetupStepView(
        number: 2,
        title: "Add Voicey",
        description: "Tap \"Add New Keyboard\" and select \"Voicey Dictation\"",
        actionLabel: nil,
        action: nil
      )

      SetupStepView(
        number: 3,
        title: "Allow Full Access",
        description: "Tap \"Voicey Dictation\" and enable \"Allow Full Access\" for microphone",
        actionLabel: nil,
        action: nil
      )

      SetupStepView(
        number: 4,
        title: "Switch to Voicey",
        description: "In any text field, long-press the globe icon and select \"Voicey Dictation\"",
        actionLabel: nil,
        action: nil
      )
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
    .cornerRadius(12)
  }

  // MARK: - Model Section

  private var modelSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Speech Models", systemImage: "cpu")
        .font(.headline)

      if !modelManager.hasDownloadedModel {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text("Download a model to enable dictation")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Text("Keyboard extensions have limited memory. Smaller models work best.")
        .font(.caption)
        .foregroundStyle(.secondary)

      ForEach(WhisperModel.extensionCompatible) { model in
        ModelRow(model: model)
      }

      DisclosureGroup("Larger Models (may not work in keyboard)") {
        ForEach(WhisperModel.allCases.filter { !$0.isSuitableForExtension }) { model in
          ModelRow(model: model)
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
    .cornerRadius(12)
  }

  private func openKeyboardSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }
}

// MARK: - Setup Step View

struct SetupStepView: View {
  let number: Int
  let title: String
  let description: String
  let actionLabel: String?
  let action: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.blue)
          .frame(width: 28, height: 28)

        Text("\(number)")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(.white)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.subheadline.weight(.medium))

        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)

        if let actionLabel = actionLabel, let action = action {
          Button(actionLabel, action: action)
            .font(.caption.weight(.medium))
            .padding(.top, 2)
        }
      }
    }
  }
}

// MARK: - Model Row

struct ModelRow: View {
  let model: WhisperModel
  @ObservedObject private var modelManager = ModelManager.shared

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(model.displayName)
            .font(.subheadline.weight(.medium))

          if model.isSuitableForExtension && model == .baseEn {
            Text("Recommended")
              .font(.caption2.weight(.medium))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.blue.opacity(0.15))
              .foregroundStyle(.blue)
              .cornerRadius(4)
          }
        }

        Text("\(model.description) • \(ModelManager.formatSize(model.diskSize))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if modelManager.isDownloading[model, default: false] {
        ProgressView()
          .frame(width: 28, height: 28)

        Button {
          modelManager.cancelDownload(model)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
      } else if modelManager.isDownloaded(model) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.title3)
      } else {
        Button {
          modelManager.downloadModel(model)
        } label: {
          Image(systemName: "arrow.down.circle")
            .foregroundStyle(.blue)
            .font(.title3)
        }
      }
    }
    .padding(.vertical, 4)
  }
}
