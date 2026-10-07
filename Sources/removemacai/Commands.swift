import AppKit
import Foundation

let version = "1.0.1"

enum Commands {
  /// How to undo, as the person ran us: the one-line installer passes its own
  /// command, a brew or source install uses the binary's name.
  static var undo: String {
    ProcessInfo.processInfo.environment["REMOVEMACAI_UNDO"] ?? "removemacai revert"
  }

  static func header() {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    print(Term.bold("RemoveMacAI") + Term.dim(" \(version)  ·  macOS \(os.majorVersion).\(os.minorVersion)"))
    print()
  }

  // MARK: status

  static func status() {
    header()
    print(Term.bold(L10n.s("Features", "功能特性")))
    for feature in Catalog.features {
      let label: String
      switch Settings.state(feature) {
      case .lockedOff: label = Term.green(L10n.s("off", "已关闭")) + Term.dim(L10n.s(" (locked)", " (已锁定)"))
      case .off: label = Term.green(L10n.s("off", "已关闭"))
      case .on: label = Term.yellow(L10n.s("on", "开启中"))
      case .unknown: label = Term.yellow(L10n.s("unknown", "未知"))
      }
      print("  " + Term.pad(feature.title, 40) + label)
    }
    print()
    if printModels() == 0 && Profile.installed().ai {
      print(Term.dim(L10n.s(
        "  macOS removes deleted model files itself, so System Settings can count them for a while.",
        "  macOS 会在后台按系统计划异步彻底删除模型文件，因此“系统设置”的占用统计可能会滞后一段时间。")))
    }
    print()
    if isOff() {
      print(Term.green(L10n.s("Apple Intelligence is off.", "Apple Intelligence 已彻底关闭。")) + Term.dim(L10n.s(" Undo with: \(undo)", " 还原命令：\(undo)")))
    } else {
      print(L10n.s("Turn it off with: ", "一键关闭请执行：") + Term.bold("removemacai"))
    }
  }

  @discardableResult
  static func printModels() -> Int64? {
    print(Term.bold(L10n.s("Models on disk", "磁盘模型占用")))
    guard Models.available() else {
      print(Term.dim(L10n.s("  Apple's asset service did not answer, so the sizes are unknown.", "  Apple 资产服务未响应，暂无法获知模型大小。")))
      return nil
    }
    var readings: [String: Int64] = [:]
    for set in Catalog.modelSets {
      let bytes = Models.bytes(set.name)
      readings[set.name] = bytes
      print("  " + Term.pad(set.title, 40) + modelSize(bytes))
    }
    let total = Models.total(Catalog.modelSets.map(\.name), read: { readings[$0] })
    print("  " + Term.pad(L10n.s("Total", "总计"), 40) + (total.map { Term.bold(Term.size($0)) } ?? Term.yellow(L10n.s("unknown", "未知"))))
    return total
  }

  static func modelSize(_ bytes: Int64?) -> String {
    guard let bytes else { return Term.yellow(L10n.s("unknown", "未知")) }
    return bytes > 0 ? Term.yellow(Term.size(bytes)) : Term.dim(L10n.s("none", "无占用"))
  }

  static func featuresOn() -> Int { Catalog.features.filter { Settings.state($0) == .on }.count }

  static func isOff() -> Bool {
    let profile = Profile.installed()
    return profile.on && profile.ai && Catalog.features.allSatisfy { Settings.state($0).isOff }
  }

  // MARK: off

  static func off(keep: Set<String>, dryRun: Bool, yes: Bool) -> Bool {
    header()
    for id in keep where Catalog.feature(id) == nil {
      Term.fail("there is no feature called \"\(id)\". The names are listed by: removemacai features")
    }
    let sets = Catalog.setsToRemove(keeping: keep)
    let modelsAvailable = sets.isEmpty || Models.available()
    let modelsBefore: Int64? = sets.isEmpty ? 0 : (modelsAvailable ? Models.total(sets) : nil)
    let profile = Profile.installed()
    let target = Profile.Contents(ai: keep, tweaks: profile.tweaks)
    let profileReady = profile.contents == target
    let offSummary = keep.isEmpty
      ? L10n.s("Apple Intelligence is off.", "Apple Intelligence 已彻底关闭。")
      : L10n.s("The selected features are off.", "所选功能已成功关闭。")

    if profileReady && modelsBefore == 0 {
      print(Term.green(offSummary) + L10n.s(" No models remain in the sets selected for removal.", " 待移除的模型集合中已无残留模型。"))
      if !sets.isEmpty {
        print(Term.dim(L10n.s(
          "macOS removes deleted model files itself, so System Settings can count them for a while.",
          "macOS 会在后台按系统计划异步彻底删除模型文件，因此“系统设置”的占用统计可能会滞后一段时间。")))
      }
      warnKeptButOff(keep)
      print(Term.dim(L10n.s("Check it with: removemacai status    Undo with: \(undo)", "查看状态：removemacai status    还原：\(undo)")))
      return true
    }

    let on = featuresOn()
    print(profileReady
      ? L10n.s("The profile is installed. Checking the selected models.", "配置描述文件已安装。正在检查相关模型。")
      : L10n.s("Checking Apple Intelligence and its models.", "正在检查 Apple Intelligence 特性及本地模型。"))
    print("  " + Term.pad(L10n.s("Features on", "开启中的特性"), 20) + "\(on) of \(Catalog.features.count)")
    print("  " + Term.pad(L10n.s("Models on disk", "磁盘模型占用"), 20) + (modelsBefore.map(Term.size) ?? L10n.s("unknown", "未知")))
    print()
    print(L10n.s("Turning it off will:", "执行关闭操作将："))
    print(L10n.s(
      "  · switch off Siri, Writing Tools, Genmoji, Image Playground, summaries and ChatGPT",
      "  · 关闭 Siri、写作工具、Genmoji、图像乐园、各类摘要以及 ChatGPT")
      + (keep.isEmpty ? "" : Term.dim(L10n.s(" (keeping ", " (保留 ") + keep.sorted().joined(separator: ", ") + ")")))
    if let modelsBefore {
      print(L10n.s("  · delete ", "  · 删除 ") + Term.bold(Term.size(modelsBefore)) + L10n.s(" of models and stop macOS downloading them again", " 本地模型并阻止 macOS 重新下载"))
    } else if modelsAvailable {
      print(L10n.s("  · request model removal and block downloads (the current model sizes are unknown)", "  · 请求清除模型并拦截下载（当前模型占用未知）"))
    } else {
      print(L10n.s("  · stop model downloads (Apple's asset service is unavailable, so removal cannot be requested)", "  · 拦截模型下载（Apple 资产服务不可用，无法请求删除）"))
    }
    if !profileReady {
      print(L10n.s("  · ask you to approve one profile in System Settings (macOS requires that click)", "  · 需要你在“系统设置”中批准并安装一个描述文件（macOS 强制交互确认）"))
    }
    print()
    print(Term.dim(L10n.s("Everything comes back with: \(undo)", "随时还原所有更改：\(undo)")))
    print()

    let data: Data
    do { data = try Profile.data(target) } catch { Term.fail("could not build the profile: \(error)") }

    if dryRun {
      let path = FileManager.default.temporaryDirectory.appendingPathComponent("RemoveMacAI.mobileconfig")
      try? data.write(to: path)
      print(Term.bold(L10n.s("Dry run, nothing changed.", "演练模式 (Dry run)，未作任何实际更改。")))
      print(L10n.s("Profile it would install:  ", "拟安装的描述文件：") + path.path)
      var deleting = sets
      var staying: [(String, String)] = []
      if modelsAvailable, let split = try? Models.matching(sets) { (deleting, staying) = (split.matched, split.skipped) }
      print(L10n.s("Models it would delete:    ", "拟删除的模型：    ") + (deleting.isEmpty ? L10n.s("none", "无") : deleting.joined(separator: ", ")))
      for (name, reason) in staying {
        print("  " + Term.yellow("!") + " \(Catalog.modelSet(name)?.title ?? name) " + L10n.s("would stay: ", "将保留：") + Term.dim(reason))
      }
      return true
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      guard Term.ask(L10n.s("Turn Apple Intelligence off?", "确定彻底关闭 Apple Intelligence 吗？")) else {
        print(L10n.s("Nothing changed.", "未做任何修改。"))
        return true
      }
      print()
    }

    // 1. The profile switches the features off and blocks the model downloads.
    if profileReady {
      print(Term.green("✓") + L10n.s(" The profile is already installed", " 描述文件已就绪"))
    } else {
      print(Term.bold(L10n.s("Step 1 of 2", "步骤 1/2")) + L10n.s("  Approve the profile", "  批准配置描述文件"))
      do { try data.write(to: Profile.file) } catch { Term.fail("could not write \(Profile.file.path): \(error)") }
      NSWorkspace.shared.open(Profile.file)
      Thread.sleep(forTimeInterval: 1)
      openProfileSettings()
      print(L10n.s("  System Settings is open. Double-click ", "  系统设置已打开。请双击 ") + Term.bold("RemoveMacAI") + L10n.s(", then click ", "，然后点击 ")
        + Term.bold(L10n.s("Install", "安装")) + "。")
      guard waitFor(L10n.s("waiting for you in System Settings", "正在等待你在系统设置中确认"), { Profile.matches(target) })
      else {
        print(L10n.s("  The profile is not installed yet. Run this again once it is, and it picks up from here.", "  描述文件尚未安装。安装完成后重新运行此命令即可继续。"))
        return false
      }
      print("  " + Term.green("✓") + L10n.s(" Profile installed", " 描述文件安装成功"))
    }

    // 2. The models go now that they cannot download again.
    let removalComplete = deleteModels(sets, step: L10n.s("Step 2 of 2", "步骤 2/2"))
    print()
    if removalComplete {
      print(Term.green(L10n.s("Done.", "已完成。")) + " " + offSummary)
    } else {
      print(Term.yellow(L10n.s("Incomplete.", "未完全完成。")) + " " + offSummary + L10n.s(" The profile remains installed; model removal is incomplete.", " 描述文件保持安装；模型删除未完全完成。"))
    }
    warnKeptButOff(keep)
    print(Term.dim(L10n.s("Check it with: removemacai status    Undo with: \(undo)", "查看状态：removemacai status    还原：\(undo)")))
    return removalComplete
  }

  /// Removes the model sets through the asset service and reports what it
  /// could confirm. Returns whether removal is complete.
  static func deleteModels(_ sets: [String], step: String) -> Bool {
    // Approval can take several minutes; use a fresh snapshot before deleting.
    let removalAvailable = sets.isEmpty || Models.available()
    var removing = sets
    var staying: [(String, String)] = []
    if removalAvailable, !sets.isEmpty {
      do { (removing, staying) = try Models.matching(sets) } catch { Term.fail("\(error)") }
    }
    for (name, reason) in staying {
      print("  " + Term.yellow("!") + " \(Catalog.modelSet(name)?.title ?? name) stayed: " + Term.dim(reason))
    }
    let removalBefore: Int64? = removing.isEmpty ? 0 : (removalAvailable ? Models.total(removing) : nil)
    var removalComplete = true
    if !removalAvailable {
      print("  " + Term.yellow("!") + " Apple's asset service is unavailable, so model removal could not be requested.")
      removalComplete = false
    } else if removalBefore != 0 {
      print(Term.bold(step) + "  Delete the models")
      do {
        let result = try removeModels(removing, before: removalBefore)
        for (name, reason) in result.failures {
          print("  " + Term.yellow("!") + " Removal request for \(Catalog.modelSet(name)?.title ?? name): " + Term.dim(reason))
        }
        removalComplete = result.complete
        if let deleted = result.deletedBytes {
          print("  " + (result.complete ? Term.green("✓") : Term.yellow("!")) + " Deleted " + Term.size(deleted))
        } else {
          print("  " + Term.dim("The amount deleted is unknown because the asset service did not report all sizes."))
        }
        if result.after == nil {
          print("  " + Term.yellow("!") + " The remaining model sizes are unknown; removal could not be confirmed.")
        } else if let remaining = result.after, remaining > 0 {
          print("  " + Term.yellow("!") + " " + Term.size(remaining) + " of selected models remain.")
        }
        if !result.verified {
          print("  " + Term.yellow("!") + " Timed out waiting to confirm that the selected models were removed.")
        }
        if result.complete {
          print("    " + Term.dim("macOS removes the files itself, so System Settings can count them under Apple Intelligence for a while."))
        }
      } catch { Term.fail("\(error)") }
    }
    return removalComplete
  }

  static func warnKeptButOff(_ keep: Set<String>) {
    for feature in Catalog.features where keep.contains(feature.id) && Settings.state(feature) == .off {
      print(Term.yellow("!") + " \(feature.title) is kept, but it is switched off. Turn it on in System Settings.")
    }
  }

  /// Injectable operations let self-tests verify failures without contacting the asset service.
  static func removeModels(
    _ sets: [String], before: Int64?,
    remove: ([String]) throws -> [(String, String)] = { try Models.remove($0) },
    total: @escaping ([String]) -> Int64? = { Models.total($0) },
    wait: (() -> Bool) -> Bool = { waitFor("deleting", $0, minutes: 0.5) }
  ) throws -> ModelRemovalResult {
    if sets.isEmpty || before == 0 {
      return ModelRemovalResult(before: before, after: 0, failures: [], verified: true)
    }
    let failures = try remove(sets)
    var after: Int64?
    let verified = wait {
      after = total(sets)
      return after == 0
    }
    return ModelRemovalResult(before: before, after: after, failures: failures, verified: verified)
  }

  // MARK: revert

  /// Undoes everything: the tweaks in the journal right away, then the
  /// profile, which macOS only lets the person remove.
  static func revert() {
    header()
    let journal = Engine.loadJournal()
    let profileOn = Profile.installed().on
    guard profileOn || !journal.entries.isEmpty else {
      print(L10n.s("RemoveMacAI hasn't changed anything on this Mac, so there is nothing to undo.", "RemoveMacAI 尚未对此 Mac 做任何更改，无需还原。"))
      return
    }
    if !journal.entries.isEmpty {
      let problems = Engine.revertAll()
      for p in problems { print("  " + Term.yellow("!") + " " + p) }
      print(Term.green("✓") + L10n.s(" Settings changed outside the profile are back as they were", " 描述文件外的各项系统设置已全部还原为修改前状态"))
    }
    if profileOn {
      guard removeProfile() else { exit(1) }
      print(Term.dim(L10n.s("macOS downloads the models again when you turn a feature back on.", "重新开启某项特性时，macOS 会按需重新下载对应的模型。")))
    }
  }

  /// Turns Apple Intelligence back on and keeps the other tweaks.
  static func on() {
    header()
    let profile = Profile.installed()
    guard profile.on && profile.ai else {
      print(L10n.s("RemoveMacAI isn't turning Apple Intelligence off, so there is nothing to undo.", "Apple Intelligence 当前未被 RemoveMacAI 关闭，无需还原。"))
      return
    }
    if profile.tweaks.isEmpty {
      guard removeProfile() else { exit(1) }
    } else {
      let target = Profile.Contents(ai: nil, tweaks: profile.tweaks)
      guard installProfile(target) else { exit(1) }
    }
    print(Term.dim(L10n.s("macOS downloads the models again when you turn a feature back on.", "重新开启某项特性时，macOS 会按需重新下载对应的模型。")))
  }

  static func removeProfile() -> Bool {
    openProfileSettings()
    print(L10n.s("System Settings is open. Select ", "系统设置已打开。请选择 ") + Term.bold("RemoveMacAI") + L10n.s(", then click ", "，然后点击 ") + Term.bold(L10n.s("Remove", "移除")) + "。")
    print(Term.dim(L10n.s("From a terminal instead: sudo profiles remove -identifier \(Profile.identifier)", "亦可在终端中执行：sudo profiles remove -identifier \(Profile.identifier)")))
    guard waitFor(L10n.s("waiting for you in System Settings", "正在等待你在系统设置中确认"), { !Profile.installed().on }) else {
      print(L10n.s("The profile is still installed. You can remove it in System Settings any time.", "描述文件仍处于安装状态。你可随时在系统设置中手动移除。"))
      return false
    }
    print(Term.green("✓") + L10n.s(" Profile removed. Your own settings apply again.", " 描述文件已移除。系统将恢复你原有的各项设置。"))
    return true
  }

  /// Shows the profile for approval and waits until it is in force.
  static func installProfile(_ target: Profile.Contents) -> Bool {
    do { try Profile.present(target) } catch {
      print(Term.red("error: ") + "could not write \(Profile.file.path): \(error)")
      return false
    }
    Thread.sleep(forTimeInterval: 1)
    openProfileSettings()
    print(L10n.s("System Settings is open. Double-click ", "系统设置已打开。请双击 ") + Term.bold("RemoveMacAI") + L10n.s(", then click ", "，然后点击 ") + Term.bold(L10n.s("Install", "安装")) + "。")
    guard waitFor(L10n.s("waiting for you in System Settings", "正在等待你在系统设置中确认"), { Profile.matches(target) }) else {
      print(L10n.s("The profile is not installed yet. Run this again once it is.", "描述文件尚未安装。安装后再次运行此命令即可。"))
      return false
    }
    print(Term.green("✓") + L10n.s(" Profile installed", " 描述文件安装成功"))
    return true
  }

  // MARK: features

  static func features() {
    for f in Catalog.features { print(Term.pad(f.id, 26) + f.title) }
  }

  // MARK: helpers

  static func openProfileSettings() {
    for url in [
      "x-apple.systempreferences:com.apple.Profiles-Settings.extension",
      "x-apple.systempreferences:com.apple.preferences.configurationprofiles",
    ] {
      if let u = URL(string: url), NSWorkspace.shared.open(u) { return }
    }
  }

  static func waitFor(_ what: String, _ condition: () -> Bool, minutes: Double = 10) -> Bool {
    let spinner = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    let deadline = Date().addingTimeInterval(minutes * 60)
    var i = 0
    defer { if Term.color { print("\r\u{1B}[K", terminator: "") } }
    while Date() < deadline {
      if condition() { return true }
      if Term.color {
        print("\r  " + Term.dim("\(spinner[i % spinner.count]) \(what)"), terminator: "")
        fflush(stdout)
      }
      i += 1
      Thread.sleep(forTimeInterval: 0.5)
    }
    return false
  }
}
