import Foundation

/// Central localization helper for bilingual (English & Simplified Chinese) support.
enum L10n {
  /// Whether the environment or current system locale prefers Chinese.
  static var isChinese: Bool {
    if let env = ProcessInfo.processInfo.environment["REMOVEMACAI_LANG"] {
      return env.lowercased().hasPrefix("zh")
    }
    for lang in Locale.preferredLanguages {
      let lower = lang.lowercased()
      if lower.hasPrefix("zh") { return true }
      if lower.hasPrefix("en") { return false }
    }
    if let code = Locale.current.language.languageCode?.identifier {
      return code.lowercased() == "zh"
    }
    return false
  }

  /// Returns Chinese text if in a Chinese locale, otherwise returns English text.
  @inline(__always)
  static func s(_ en: String, _ zh: String) -> String {
    isChinese ? zh : en
  }
}
