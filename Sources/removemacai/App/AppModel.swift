import AppKit
import Observation
import SwiftUI

enum Page: Hashable {
  case overview, intelligence, group(TweakGroup), background, storage, changes

  var title: String {
    switch self {
    case .overview: return L10n.s("Overview", "系统概览")
    case .intelligence: return "Apple Intelligence"
    case .group(let g): return g.title
    case .background: return L10n.s("Background Items", "后台启动项")
    case .storage: return L10n.s("Storage", "空间清理")
    case .changes: return L10n.s("Undo", "更改与还原")
    }
  }

  var symbol: String {
    switch self {
    case .overview: return "gauge.with.dots.needle.33percent"
    case .intelligence: return "apple.intelligence"
    case .group(let g): return g.symbol
    case .background: return "gearshape.2"
    case .storage: return "internaldrive"
    case .changes: return "arrow.uturn.backward"
    }
  }
}

/// What the app is doing after Apply.
enum RunState: Equatable {
  case working(String)
  case approveProfile(remove: Bool)
  case finished(problems: [String], freed: Int64?)
}

@MainActor @Observable
final class AppModel {
  var page: Page? = .overview

  // What the Mac looks like now.
  var snapshot = Snapshot()
  var featureStates: [String: FeatureState] = [:]
  var modelBytes: [String: Int64] = [:]
  var modelsAvailable = true
  var loadingModels = true
  var journal = Engine.loadJournal()

  // What the person wants.
  var wanted: Set<String> = []
  var aiOff = false
  var aiKept: Set<String> = []

  var background: [BackgroundItem] = []
  var backgroundOff: Set<String> = []
  var backgroundBusy = false

  var storage: [StorageItem] = []
  var storageChosen: Set<String> = []
  var scanning = false
  var scanned = false
  var cleaning = false
  var cleanMessage: String?

  var reviewing = false
  var run: RunState?
  private var cancelWait = false

  static weak var shared: AppModel?

  init() {
    reload(resetChoices: true)
    AppModel.shared = self
  }

  // MARK: reading

  var currentAI: Set<String>? { snapshot.profile.on && snapshot.profile.ai ? snapshot.profile.kept : nil }
  var targetAI: Set<String>? { aiOff ? aiKept : nil }

  /// Each tweak's state, read once per reload; the views ask for it on every redraw.
  var states: [String: TweakState] = [:]

  func reload(resetChoices: Bool) {
    snapshot = Snapshot()
    states = Dictionary(uniqueKeysWithValues: Tweaks.all.map { ($0.id, snapshot.state($0)) })
    journal = Engine.loadJournal()
    if resetChoices {
      wanted = Set(states.filter { $0.value == .applied }.map(\.key))
      aiOff = currentAI != nil
      aiKept = snapshot.profile.ai ? snapshot.profile.kept : []
    }
    loadBackground()
    loadModels()
  }

  func loadModels() {
    loadingModels = true
    Task.detached(priority: .userInitiated) {
      let available = Models.available()
      var bytes: [String: Int64] = [:]
      if available {
        for set in Catalog.modelSets { if let b = Models.bytes(set.name) { bytes[set.name] = b } }
      }
      let states = Dictionary(uniqueKeysWithValues: Catalog.features.map { ($0.id, Settings.state($0)) })
      let sizes = bytes
      await MainActor.run {
        self.modelsAvailable = available
        self.modelBytes = sizes
        self.featureStates = states
        self.loadingModels = false
      }
    }
  }

  var modelTotal: Int64 { modelBytes.values.reduce(0, +) }

  func loadBackground() {
    background = BackgroundItems.scan()
    let labels = BackgroundItems.disabledLabels()
    backgroundOff = Set(background.filter { BackgroundItems.isDisabled($0, labels) }.map(\.id))
  }

  func state(_ tweak: Tweak) -> TweakState { states[tweak.id] ?? snapshot.state(tweak) }

  func isOn(_ tweak: Tweak) -> Bool { wanted.contains(tweak.id) }

  func toggle(_ tweak: Tweak, _ on: Bool) {
    if on { wanted.insert(tweak.id) } else { wanted.remove(tweak.id) }
  }

  func choose(_ preset: Preset) {
    wanted.formUnion(Tweaks.preset(preset).map(\.id))
    aiOff = true
  }

  var appliedCount: Int { states.values.filter { $0 == .applied }.count }
  var availableCount: Int { Tweaks.all.filter { let s = state($0); return s != .unsupported && s != .managed }.count }

  /// Tweaks whose wanted state differs from the Mac.
  var pendingTweaks: [(tweak: Tweak, apply: Bool)] {
    Tweaks.all.compactMap { t in
      let s = state(t)
      guard s != .managed && s != .unsupported else { return nil }
      let want = wanted.contains(t.id)
      if want && s != .applied { return (t, true) }
      if !want && s != .notApplied { return (t, false) }
      return nil
    }
  }

  var aiPending: Bool { targetAI != currentAI }
  var pendingCount: Int { pendingTweaks.count + (aiPending ? 1 : 0) }

  func pending(in group: TweakGroup) -> Int { pendingTweaks.filter { $0.tweak.group == group }.count }

  func discard() { reload(resetChoices: true) }

  func plan() -> Plan { Plan.make(wanted: wanted, ai: targetAI, snapshot: snapshot) }

  // MARK: applying

  func apply() {
    let plan = plan()
    reviewing = false
    run = .working("Changing settings")
    cancelWait = false
    let before = modelTotal
    Task.detached(priority: .userInitiated) {
      var problems = Engine.runLocal(plan)
      var freed: Int64? = nil
      if let target = plan.profile {
        await MainActor.run { self.run = .approveProfile(remove: target.isEmpty) }
        if !target.isEmpty {
          do { try Profile.present(target) } catch { problems.append("Could not write the profile: \(error)") }
          try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await MainActor.run { Commands.openProfileSettings() }
        let approved = await self.waitFor { target.isEmpty ? !Profile.installed().on : Profile.matches(target) }
        if !approved {
          problems.append(
            target.isEmpty
              ? "The profile is still installed. Remove RemoveMacAI in System Settings > General > Device Management."
              : "The profile wasn't approved, so the locked settings and Apple Intelligence didn't change.")
        }
      }
      // Models only go once the profile blocks their download.
      if !plan.models.isEmpty && Profile.installed().ai {
        await MainActor.run { self.run = .working(L10n.s("Deleting Apple Intelligence models", "正在清理 Apple Intelligence 模型...")) }
        let result = Self.deleteModels(plan.models)
        problems += result.problems
        freed = result.freed ?? (before > 0 ? before : nil)
      }
      let outcome = RunState.finished(problems: problems, freed: freed)
      await MainActor.run {
        self.run = outcome
        self.reload(resetChoices: true)
      }
    }
  }

  nonisolated static func deleteModels(_ sets: [String]) -> (problems: [String], freed: Int64?) {
    guard Models.available() else { return ([L10n.s("Apple's asset service didn't answer, so the models stay for now.", "Apple 资产服务未响应，模型暂时保留。")], nil) }
    var problems: [String] = []
    var removing = sets
    do {
      let split = try Models.matching(sets)
      removing = split.matched
      problems += split.skipped.map { "\(Catalog.modelSet($0.0)?.title ?? $0.0) " + L10n.s("stayed: ", "已保留：") + "\($0.1)" }
    } catch { return (["\(error)"], nil) }
    let before = Models.total(removing)
    do {
      let result = try Commands.removeModels(removing, before: before)
      problems += result.failures.map { "\(Catalog.modelSet($0.0)?.title ?? $0.0): \($0.1)" }
      if !result.verified { problems.append(L10n.s("Removal couldn't be confirmed yet. Check again in a minute.", "模型删除尚未能即时确认，请稍后刷新查看。")) }
      return (problems, result.deletedBytes)
    } catch {
      return (problems + ["\(error)"], nil)
    }
  }

  /// Polls until the condition holds, Cancel is pressed, or ten minutes pass.
  nonisolated func waitFor(_ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(600)
    while Date() < deadline {
      if condition() { return true }
      if await MainActor.run(body: { self.cancelWait }) { return false }
      try? await Task.sleep(nanoseconds: 700_000_000)
    }
    return false
  }

  func cancel() { cancelWait = true }

  /// Deletes models left on disk while Apple Intelligence is already off.
  func deleteLeftoverModels() {
    guard let kept = currentAI else { return }
    run = .working(L10n.s("Deleting Apple Intelligence models", "正在清理 Apple Intelligence 模型..."))
    Task.detached(priority: .userInitiated) {
      let sets = Catalog.setsToRemove(keeping: kept).filter { Models.present($0) }
      let result = Self.deleteModels(sets)
      let outcome = RunState.finished(problems: result.problems, freed: result.freed)
      await MainActor.run {
        self.run = outcome
        self.reload(resetChoices: false)
      }
    }
  }

  func dismissRun() { run = nil }

  // MARK: undo

  func undoEverything() {
    run = .working(L10n.s("Undoing changes", "正在还原各项设置..."))
    cancelWait = false
    Task.detached(priority: .userInitiated) {
      var problems = Engine.revertAll()
      if Profile.installed().on {
        await MainActor.run {
          self.run = .approveProfile(remove: true)
          Commands.openProfileSettings()
        }
        if !(await self.waitFor { !Profile.installed().on }) {
          problems.append(L10n.s(
            "The profile is still installed. Remove RemoveMacAI in System Settings > General > Device Management.",
            "描述文件仍处于安装状态。请前往“系统设置 > 通用 > 设备管理”中移除 RemoveMacAI。"))
        }
      }
      let outcome = RunState.finished(problems: problems, freed: nil)
      await MainActor.run {
        self.run = outcome
        self.reload(resetChoices: true)
      }
    }
  }

  // MARK: background items

  func setBackground(_ item: BackgroundItem, off: Bool) {
    backgroundBusy = true
    Task.detached(priority: .userInitiated) {
      let problems = BackgroundItems.set([item], disabled: off)
      await MainActor.run {
        self.backgroundBusy = false
        self.loadBackground()
        self.journal = Engine.loadJournal()
        if !problems.isEmpty { self.run = .finished(problems: problems, freed: nil) }
      }
    }
  }

  // MARK: storage

  func scan() {
    scanning = true
    cleanMessage = nil
    Task.detached(priority: .userInitiated) {
      let items = Storage.scan()
      await MainActor.run {
        self.storage = items
        self.storageChosen = Set(items.filter { ["derived-data", "installers", "ios-firmware", "simulators"].contains($0.id) }.map(\.id))
        self.scanning = false
        self.scanned = true
      }
    }
  }

  var chosenBytes: Int64 { storage.filter { storageChosen.contains($0.id) }.reduce(0) { $0 + $1.bytes } }

  func clean() {
    let chosen = storage.filter { storageChosen.contains($0.id) }
    let total = chosenBytes
    cleaning = true
    Task.detached(priority: .userInitiated) {
      let result = Storage.clean(chosen)
      let items = Storage.scan()
      let left = items.filter { chosen.map(\.id).contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
      var message = L10n.s(
        "Moved \(Term.size(max(0, total - left))) to the Trash. Empty the Trash to free the space.",
        "已将 \(Term.size(max(0, total - left))) 移至废纸篓。清倒废纸篓即可释放存储空间。")
      if result.protected > 0 {
        message += L10n.s(
          " \(result.protected) item\(result.protected == 1 ? "" : "s") macOS protects stayed where \(result.protected == 1 ? "it was" : "they were").",
          " 受系统完整性保护的 \(result.protected) 个项目已保留在原位。")
      }
      if !result.problems.isEmpty { message += "\n" + result.problems.joined(separator: "\n") }
      let finalMessage = message
      await MainActor.run {
        self.cleaning = false
        self.storage = items
        self.storageChosen = []
        self.cleanMessage = finalMessage
      }
    }
  }
}
