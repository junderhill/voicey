import Foundation

// MARK: - Voice Command Types

public enum VoiceCommandAction: Codable, Equatable {
  case newLine
  case newParagraph
  case scratchThat
  case custom(String)
}

public struct VoiceCommand: Identifiable, Codable {
  public let id: UUID
  public var phrase: String
  public var action: VoiceCommandAction
  public var enabled: Bool

  public init(id: UUID, phrase: String, action: VoiceCommandAction, enabled: Bool) {
    self.id = id
    self.phrase = phrase
    self.action = action
    self.enabled = enabled
  }

  public static let defaults: [VoiceCommand] = [
    VoiceCommand(id: UUID(), phrase: "new line", action: .newLine, enabled: true),
    VoiceCommand(id: UUID(), phrase: "new paragraph", action: .newParagraph, enabled: true),
    VoiceCommand(id: UUID(), phrase: "scratch that", action: .scratchThat, enabled: true)
  ]
}
