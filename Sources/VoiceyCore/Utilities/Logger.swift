import Foundation
import os

/// App-wide loggers using os.Logger for proper system integration
public enum AppLogger {
  public static let audio = Logger(subsystem: "work.voicey.Voicey", category: "audio")
  public static let transcription = Logger(subsystem: "work.voicey.Voicey", category: "transcription")
  public static let output = Logger(subsystem: "work.voicey.Voicey", category: "output")
  // swiftlint:disable:next identifier_name
  public static let ui = Logger(subsystem: "work.voicey.Voicey", category: "ui")
  public static let general = Logger(subsystem: "work.voicey.Voicey", category: "general")
  public static let model = Logger(subsystem: "work.voicey.Voicey", category: "model")
}

public func log(_ message: String) {
  AppLogger.general.info("\(message)")
}

/// Debug print that outputs directly to terminal (visible when running from command line)
public func debugPrint(_ message: String, category: String = "DEBUG") {
  let timestamp = ISO8601DateFormatter().string(from: Date())
  print("[\(timestamp)] [\(category)] \(message)")
  fflush(stdout)
}
