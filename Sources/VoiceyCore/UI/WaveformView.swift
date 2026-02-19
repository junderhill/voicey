import SwiftUI

/// Real-time audio waveform visualization
public struct WaveformView: View {
  public let level: Float

  @State private var levels: [CGFloat] = Array(repeating: 0.1, count: 12)
  @State private var timer: Timer?
  @State private var lastLevel: Float = 0

  public init(level: Float) {
    self.level = level
  }

  public var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<levels.count, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(barColor(for: index))
          .frame(width: 4, height: barHeight(for: index))
          .animation(.easeOut(duration: 0.1), value: levels[index])
      }
    }
    .frame(maxHeight: .infinity)
    .onChange(of: level) { newLevel in
      lastLevel = newLevel
    }
    .onAppear {
      startTimer()
    }
    .onDisappear {
      stopTimer()
    }
  }

  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
      updateLevels(with: lastLevel)
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func barHeight(for index: Int) -> CGFloat {
    max(4, levels[index] * 24)
  }

  private func barColor(for index: Int) -> Color {
    let intensity = levels[index]
    if intensity > 0.7 {
      return .red
    } else if intensity > 0.4 {
      return .orange
    } else {
      return .green
    }
  }

  private func updateLevels(with newLevel: Float) {
    var newLevels = levels
    newLevels.removeFirst()

    let baseLevel = CGFloat(newLevel)
    let variationRange = baseLevel < 0.2 ? 0.05 : 0.1
    let variation = CGFloat.random(in: -variationRange...variationRange)
    let adjustedLevel = max(0.05, min(1.0, baseLevel + variation))

    newLevels.append(adjustedLevel)
    levels = newLevels
  }
}

/// Alternative meter-style visualization
public struct LevelMeterView: View {
  public let level: Float

  private let segments = 10

  public init(level: Float) {
    self.level = level
  }

  public var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<segments, id: \.self) { index in
        RoundedRectangle(cornerRadius: 2)
          .fill(segmentColor(for: index))
          .opacity(segmentOpacity(for: index))
      }
    }
    .animation(.easeOut(duration: 0.05), value: level)
  }

  private func segmentColor(for index: Int) -> Color {
    let position = CGFloat(index) / CGFloat(segments)
    if position > 0.8 {
      return .red
    } else if position > 0.6 {
      return .orange
    } else {
      return .green
    }
  }

  private func segmentOpacity(for index: Int) -> Double {
    let threshold = CGFloat(index) / CGFloat(segments)
    return CGFloat(level) >= threshold ? 1.0 : 0.3
  }
}

/// Circular audio level indicator
public struct CircularLevelView: View {
  public let level: Float

  public init(level: Float) {
    self.level = level
  }

  public var body: some View {
    ZStack {
      Circle()
        .stroke(Color.gray.opacity(0.3), lineWidth: 3)

      Circle()
        .trim(from: 0, to: CGFloat(level))
        .stroke(
          levelGradient,
          style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(.easeOut(duration: 0.1), value: level)

      Image(systemName: "mic.fill")
        .font(.system(size: 16))
        .foregroundStyle(level > 0.1 ? .red : .gray)
    }
  }

  private var levelGradient: LinearGradient {
    LinearGradient(
      colors: [.green, .yellow, .orange, .red],
      startPoint: .leading,
      endPoint: .trailing
    )
  }
}

#Preview("Waveform") {
  WaveformView(level: 0.5)
    .frame(width: 100, height: 30)
    .padding()
}

#Preview("Level Meter") {
  LevelMeterView(level: 0.7)
    .frame(width: 100, height: 20)
    .padding()
}

#Preview("Circular") {
  CircularLevelView(level: 0.6)
    .frame(width: 40, height: 40)
    .padding()
}
