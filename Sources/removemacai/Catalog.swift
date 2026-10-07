import Foundation

/// A preference the profile forces while a feature is off.
struct ForcedPreference: Equatable {
  let domain: String
  let key: String
  let off: Bool
}

/// One thing a person can switch off, the switches it takes, and the model
/// sets it needs. Keys and sets for macOS 27 were first mapped by pared
/// (github.com/4evy/pared, MIT).
struct Feature {
  let id: String
  let title: String
  let restrictions: [String]
  let preferences: [ForcedPreference]
  let modelSets: [String]
}

/// A downloadable model set in Apple's asset service.
struct ModelSet {
  let name: String
  let assetType: String
  let title: String
}

enum Catalog {
  static let foundationModels = "com.apple.modelcatalog"
  static let visualModels = "com.apple.MobileAsset.UAF.FM.Visual"
  static let codeModels = "com.apple.MobileAsset.UAF.FM.CodeLM"
  static let cleanUpModels = "com.apple.MobileAsset.UAF.Photos.MagicCleanup"
  static let spatialModels = "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive"

  static var modelSets: [ModelSet] {
    [
      ModelSet(
        name: foundationModels, assetType: "com.apple.MobileAsset.UAF.FM.GenerativeModels",
        title: L10n.s("Apple Intelligence foundation models", "Apple Intelligence 基础大模型")),
      ModelSet(
        name: visualModels, assetType: visualModels,
        title: L10n.s("Image and Genmoji models", "图像与 Genmoji 生成模型")),
      ModelSet(
        name: spatialModels, assetType: spatialModels,
        title: L10n.s("Spatial Photos models", "空间照片模型")),
      ModelSet(
        name: cleanUpModels, assetType: cleanUpModels,
        title: L10n.s("Photos Clean Up models", "照片消除模型")),
      ModelSet(
        name: codeModels, assetType: codeModels,
        title: L10n.s("Xcode code completion models", "Xcode 代码补全模型")),
    ]
  }

  static var features: [Feature] {
    [
      Feature(
        id: "siri", title: L10n.s("Siri and Siri AI", "Siri 与 Siri AI"), restrictions: ["allowAssistant"],
        preferences: [
          ForcedPreference(domain: "com.apple.assistant.support", key: "Assistant Enabled", off: false),
          ForcedPreference(domain: "com.apple.Siri", key: "StatusMenuVisible", off: false),
          ForcedPreference(domain: "com.apple.Siri", key: "VoiceTriggerUserEnabled", off: false),
        ], modelSets: [foundationModels]),
      Feature(
        id: "chatgpt", title: L10n.s("ChatGPT and other AI extensions", "ChatGPT 及其他 AI 扩展"),
        restrictions: [
          "allowExternalIntelligenceIntegrations", "allowExternalIntelligenceIntegrationsSignIn",
        ], preferences: [], modelSets: []),
      Feature(
        id: "writing-tools", title: L10n.s("Writing Tools", "写作工具"), restrictions: ["allowWritingTools"],
        preferences: [], modelSets: [foundationModels]),
      Feature(
        id: "genmoji", title: L10n.s("Genmoji", "Genmoji 原创表情"), restrictions: ["allowGenmoji"], preferences: [],
        modelSets: [foundationModels, visualModels]),
      Feature(
        id: "image-playground", title: L10n.s("Image Playground", "图像乐园 (Image Playground)"),
        restrictions: ["allowImagePlayground"], preferences: [], modelSets: [foundationModels, visualModels]),
      Feature(
        id: "mail", title: L10n.s("Mail summaries and smart replies", "邮件摘要与智能回复"),
        restrictions: ["allowMailSummary", "allowMailSmartReplies"],
        preferences: [
          ForcedPreference(
            domain: "group.com.apple.mail", key: "DisableAutomaticMessageSummarization", off: true),
          ForcedPreference(domain: "group.com.apple.mail", key: "PersonalizedSmartReplies", off: false),
        ], modelSets: [foundationModels]),
      Feature(
        id: "notification-summaries", title: L10n.s("Notification summaries", "通知摘要"), restrictions: [],
        preferences: [
          ForcedPreference(domain: "group.com.apple.usernoted", key: "summarize_previews", off: false)
        ], modelSets: [foundationModels]),
      Feature(
        id: "messages-summaries", title: L10n.s("Messages summaries", "信息摘要"), restrictions: [],
        preferences: [
          ForcedPreference(domain: "group.com.apple.MobileSMS", key: "messageSummarizationEnabled", off: false)
        ], modelSets: [foundationModels]),
      Feature(
        id: "safari-summaries", title: L10n.s("Safari summaries", "Safari 网页摘要"),
        restrictions: ["allowSafariSummary"], preferences: [], modelSets: [foundationModels]),
      Feature(
        id: "notes-summaries", title: L10n.s("Notes transcription summaries", "备忘录转录摘要"),
        restrictions: ["allowNotesTranscriptionSummary"], preferences: [],
        modelSets: [foundationModels]),
      Feature(
        id: "inline-predictions", title: L10n.s("Inline text predictions", "内联输入预测"), restrictions: [],
        preferences: [
          ForcedPreference(
            domain: ".GlobalPreferences", key: "NSAutomaticInlinePredictionEnabled", off: false)
        ], modelSets: []),
      Feature(
        id: "spatial-photos", title: L10n.s("Spatial Photos", "空间照片"), restrictions: [],
        preferences: [
          ForcedPreference(domain: "com.apple.spatialphotosrelive", key: "LocallyDisabled", off: true)
        ], modelSets: [spatialModels]),
      Feature(
        id: "photos-clean-up", title: L10n.s("Photos Clean Up", "照片消除 (Clean Up)"), restrictions: [], preferences: [],
        modelSets: [cleanUpModels]),
      Feature(
        id: "xcode-completion", title: L10n.s("Xcode predictive code completion", "Xcode 代码预测补全"), restrictions: [],
        preferences: [], modelSets: [codeModels]),
    ]
  }

  static func feature(_ id: String) -> Feature? { features.first { $0.id == id } }

  static func modelSet(_ name: String) -> ModelSet? { modelSets.first { $0.name == name } }

  /// The sets to remove: every set whose features are all being turned off.
  /// A set that a kept feature still needs stays.
  static func setsToRemove(keeping kept: Set<String>) -> [String] {
    modelSets.map(\.name).filter { set in
      let users = features.filter { $0.modelSets.contains(set) }
      return !users.isEmpty && users.allSatisfy { !kept.contains($0.id) }
    }
  }
}
