import Foundation

/// Utilities for text cleanup and formatting in transcription output
public enum TextCleanup {
  public static let defaultTextExpansions: [String: String] = [
    "etcetera": "etc.",
    "et cetera": "etc.",
    "for example": "e.g.",
    "that is": "i.e.",
    "versus": "vs.",
    "mister": "Mr.",
    "missus": "Mrs.",
    "doctor": "Dr.",
    "okay": "OK",
    "o k": "OK"
  ]

  public static func capitalizeFirst(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
  }

  public static func isConjunction(_ text: String) -> Bool {
    let conjunctions = [
      "and", "but", "or", "so", "yet", "for", "nor",
      "because", "although", "while", "if", "when"
    ]
    let firstWord = text.lowercased().split(separator: " ").first.map(String.init) ?? ""
    return conjunctions.contains(firstWord)
  }

  public static func applyExpansions(_ text: String, expansions: [String: String]) -> String {
    var result = text

    for (spoken, written) in expansions {
      let pattern = "\\b\(NSRegularExpression.escapedPattern(for: spoken))\\b"
      guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: .caseInsensitive
      ) else { continue }
      result = regex.stringByReplacingMatches(
        in: result,
        range: NSRange(result.startIndex..., in: result),
        withTemplate: written
      )
    }

    return result
  }

  public static func capitalizeI(_ text: String) -> String {
    var result = text
    result = result.replacingOccurrences(of: " i ", with: " I ")
    result = result.replacingOccurrences(of: " i'", with: " I'")
    if result.hasPrefix("i ") {
      result = "I" + result.dropFirst()
    }
    return result
  }

  public static func cleanupSpacingAndPunctuation(_ text: String) -> String {
    var result = text

    while result.contains("  ") {
      result = result.replacingOccurrences(of: "  ", with: " ")
    }

    result = result.replacingOccurrences(of: " .", with: ".")
    result = result.replacingOccurrences(of: " ,", with: ",")
    result = result.replacingOccurrences(of: " ?", with: "?")
    result = result.replacingOccurrences(of: " !", with: "!")

    result = result.replacingOccurrences(of: "..", with: ".")
    result = result.replacingOccurrences(of: ",,", with: ",")
    result = result.replacingOccurrences(of: "....", with: "...")

    let punctuationPattern = "([.!?,])([A-Za-z])"
    if let regex = try? NSRegularExpression(pattern: punctuationPattern) {
      result = regex.stringByReplacingMatches(
        in: result,
        range: NSRange(result.startIndex..., in: result),
        withTemplate: "$1 $2"
      )
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
