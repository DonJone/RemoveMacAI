import AppKit
import SwiftUI

struct RemoveMacAIApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  private var _model = SwiftUI.State(initialValue: AppModel())
  private var model: AppModel {
    get { _model.wrappedValue }
    nonmutating set { _model.wrappedValue = newValue }
  }

  init() {}

  var body: some Scene {
    Window("RemoveMacAI", id: "main") {
      ContentView()
        .environment(model)
        .frame(minWidth: 860, minHeight: 600)
    }
    .defaultSize(width: 1000, height: 700)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(replacing: .appInfo) {
        Button(L10n.s("About RemoveMacAI", "关于 RemoveMacAI")) { AppDelegate.showAbout() }
      }
      CommandGroup(after: .toolbar) {
        Button(L10n.s("Reload", "重新载入")) { model.reload(resetChoices: true) }.keyboardShortcut("r")
      }
      CommandGroup(replacing: .help) {
        Link(L10n.s("RemoveMacAI on GitHub", "RemoveMacAI 的 GitHub 仓库"), destination: URL(string: "https://github.com/omlahore/RemoveMacAI")!)
        Link(L10n.s("Report a Problem", "报告问题 / 建议"), destination: URL(string: "https://github.com/omlahore/RemoveMacAI/issues/new/choose")!)
      }
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // A bare binary run from Terminal has no bundle, so it must ask to be a real app.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    #if DEBUG
      if let dir = ProcessInfo.processInfo.environment["REMOVEMACAI_SNAPSHOTS"] { Snapshots.run(into: dir) }
    #endif
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  static func showAbout() {
    let credits = NSMutableAttributedString(
      string: L10n.s(
        "Debloats macOS and can undo every change.\n\nThe Apple Intelligence part builds on pared by 4evy, which first mapped Apple's asset service and model sets.",
        "为 macOS 瘦身净化，支持随时无损还原每一项更改。\n\nApple Intelligence 移除部分基于 4evy 的 pared 项目构建，率先映射了 Apple 资源服务和模型资产集合。"
      ),
      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: "RemoveMacAI",
      .applicationVersion: version,
      .version: "",
      .credits: credits,
    ])
  }
}
