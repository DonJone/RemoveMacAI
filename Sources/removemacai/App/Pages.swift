import SwiftUI

// MARK: - Overview

struct OverviewView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Form {
      Section {
        StatusRow(
          symbol: "apple.intelligence", title: "Apple Intelligence",
          value: aiText, good: model.currentAI != nil
        ) { model.page = .intelligence }
        StatusRow(
          symbol: "slider.horizontal.3", title: L10n.s("Tweaks", "系统优化项"),
          value: L10n.s("\(model.appliedCount) of \(model.availableCount) applied", "已应用 \(model.appliedCount) / \(model.availableCount) 项"), good: model.appliedCount > 0
        ) { model.page = .group(.privacy) }
        StatusRow(
          symbol: "gearshape.2", title: L10n.s("Background items from other apps", "其他应用的后台项目"),
          value: backgroundText, good: model.background.isEmpty || !model.backgroundOff.isEmpty
        ) { model.page = .background }
        StatusRow(
          symbol: "internaldrive", title: L10n.s("Space you can get back", "预计可释放空间"),
          value: model.scanned ? Term.size(model.storage.reduce(0) { $0 + $1.bytes }) : L10n.s("Not scanned yet", "尚未扫描"), good: false
        ) { model.page = .storage }
      } header: {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 6) {
            Text(L10n.s("Debloat this Mac", "为这台 Mac 瘦身加速"))
              .font(.system(size: 28, weight: .bold))
              .foregroundStyle(.primary)
            Text(L10n.s("Turn off Apple Intelligence, analytics and the pop-ups macOS adds, and get disk space back. You see every change before it happens, and you can undo all of it.", "关闭 Apple Intelligence、系统诊断分析及 macOS 提示弹窗，并回收磁盘空间。所有更改在应用前均可预览，且随时支持一键完整还原。"))
              .font(.body)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Text(L10n.s("Apple Intelligence removal builds on [pared](https://github.com/4evy/pared) by 4evy.", "Apple Intelligence 移除逻辑基于 4evy 开发的 [pared](https://github.com/4evy/pared)。"))
              .font(.callout)
              .foregroundStyle(.tertiary)
              .tint(.secondary)
          }
          Text(L10n.s("This Mac", "当前 Mac 状态"))
        }
        .textCase(nil)
        .padding(.top, 4)
      }

      Section {
        ForEach(Preset.allCases) { preset in
          HStack(alignment: .top, spacing: 14) {
            Image(systemName: preset == .recommended ? "checkmark.seal" : "hand.raised")
              .font(.title2).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
              Text(preset.title).font(.headline)
              Text(preset.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              Text(L10n.s("\(Tweaks.preset(preset).count) tweaks and Apple Intelligence off", "\(Tweaks.preset(preset).count) 项优化并关闭 Apple Intelligence"))
                .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(L10n.s("Choose…", "选择…")) {
              model.choose(preset)
              model.reviewing = true
            }
          }
          .padding(.vertical, 4)
        }
      } header: {
        Text(L10n.s("Start with a preset", "从预设方案开始"))
      } footer: {
        Footer(L10n.s("A preset adds to what's already applied and changes nothing until you review it. Pick single tweaks in the sidebar.", "预设方案会在当前已应用配置的基础上叠加，在您确认审核前不会修改任何系统设置。如需按单项精细调整，请在左侧边栏中选择对应分组。"))
      }
    }
    .formStyle(.grouped)
    .navigationTitle(L10n.s("Overview", "系统概览"))
  }

  var aiText: String {
    if model.currentAI != nil {
      return model.modelTotal > 0
        ? L10n.s("Off, \(Term.size(model.modelTotal)) of models still on disk", "已关闭，磁盘仍残留 \(Term.size(model.modelTotal)) 模型")
        : L10n.s("Off", "已关闭")
    }
    if model.loadingModels { return L10n.s("On", "已开启") }
    return model.modelTotal > 0
      ? L10n.s("On, \(Term.size(model.modelTotal)) of models", "已开启，模型占用 \(Term.size(model.modelTotal))")
      : L10n.s("On", "已开启")
  }

  var backgroundText: String {
    let n = model.background.count
    if n == 0 { return L10n.s("None", "无") }
    let off = model.backgroundOff.count
    return off > 0
      ? L10n.s("\(n), \(off) turned off", "\(n) 项，已禁用 \(off) 项")
      : L10n.s("\(n) running", "\(n) 项正在运行")
  }
}

struct StatusRow: View {
  let symbol: String
  let title: String
  let value: String
  let good: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
        Text(title)
        Spacer()
        Text(value).foregroundStyle(good ? Color.green : Color.secondary)
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Apple Intelligence

struct IntelligenceView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Form {
      Section {
        Toggle(isOn: $model.aiOff) {
          VStack(alignment: .leading, spacing: 3) {
            Text(L10n.s("Turn off Apple Intelligence", "彻底关闭 Apple Intelligence")).font(.headline)
            Text(L10n.s("Turns off Siri, Writing Tools, Genmoji, Image Playground, summaries and ChatGPT, deletes the models and stops macOS downloading them again.", "关闭 Siri、写作工具、Genmoji、图像乐园、内容摘要与 ChatGPT 集成，删除本地大模型文件并阻止 macOS 重新静默下载。"))
              .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
        }
        .toggleStyle(.switch)
      } footer: {
        Footer(L10n.s("macOS asks you to approve a configuration profile for this. Undo puts everything back. This part builds on pared by 4evy, which first mapped Apple's asset service and model sets.", "此操作需要您在“系统设置”中批准配置描述文件。还原操作可将所有设置恢复如初。该部分基于 4evy 的 pared 项目构建，率先映射了 Apple 资源服务和模型资产集合。"))
      }

      Section {
        ForEach(Catalog.features, id: \.id) { feature in
          Toggle(isOn: Binding(
            get: { model.aiKept.contains(feature.id) },
            set: { if $0 { model.aiKept.insert(feature.id) } else { model.aiKept.remove(feature.id) } }
          )) {
            VStack(alignment: .leading, spacing: 2) {
              Text(feature.title)
              Text(stateText(feature.id)).font(.caption).foregroundStyle(.secondary)
            }
          }
          .disabled(!model.aiOff)
        }
      } header: {
        Text(L10n.s("Keep these on", "保留以下特性"))
      } footer: {
        Footer(L10n.s("A kept feature keeps the models it needs.", "被保留的特性会保留其所依赖的端侧模型。"))
      }

      Section {
        if model.loadingModels {
          HStack { ProgressView().controlSize(.small); Text(L10n.s("Asking Apple's asset service…", "正在查询 Apple 资源服务…")).foregroundStyle(.secondary) }
        } else if !model.modelsAvailable {
          Text(L10n.s("Apple's asset service didn't answer, so the sizes are unknown.", "Apple 资源服务未响应，暂无法获取确切占用大小。")).foregroundStyle(.secondary)
        } else {
          ForEach(Catalog.modelSets, id: \.name) { set in
            LabeledContent(set.title) {
              let bytes = model.modelBytes[set.name] ?? 0
              Text(bytes > 0 ? Term.size(bytes) : L10n.s("None", "无")).foregroundStyle(bytes > 0 ? .primary : .secondary)
            }
          }
          LabeledContent(L10n.s("Total", "总计")) { Text(Term.size(model.modelTotal)).fontWeight(.semibold) }
          if model.currentAI != nil && model.modelTotal > 0 {
            HStack {
              Text(L10n.s("Apple Intelligence is off, but these models are still on disk.", "Apple Intelligence 已关闭，但磁盘上仍存有这些模型文件。")).foregroundStyle(.secondary)
              Spacer()
              Button(L10n.s("Delete Models", "删除模型")) { model.deleteLeftoverModels() }
            }
          }
        }
      } header: {
        Text(L10n.s("Models on disk", "磁盘上的模型文件"))
      } footer: {
        Footer(L10n.s("macOS deletes the files on its own schedule, so Storage settings can count them for a while after removal.", "macOS 会按其自身的计划回收文件，因此“存储空间”设置在移除后的一段时间内可能仍会显示其占用。"))
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Apple Intelligence")
  }

  func stateText(_ id: String) -> String {
    switch model.featureStates[id] {
    case .lockedOff?: return L10n.s("Off, locked by RemoveMacAI", "已关闭，由 RemoveMacAI 锁定")
    case .off?: return L10n.s("Off", "已关闭")
    case .on?: return L10n.s("On", "已开启")
    default: return model.loadingModels ? L10n.s("Checking…", "检测中…") : L10n.s("Unknown", "未知")
    }
  }
}

// MARK: - Tweak groups

struct TweakGroupView: View {
  @Environment(AppModel.self) private var model
  let group: TweakGroup

  var tweaks: [Tweak] { Tweaks.all.filter { $0.group == group } }

  var body: some View {
    Form {
      Section {
        ForEach(tweaks) { TweakRow(tweak: $0) }
      } header: {
        Text(group.summary).font(.body).foregroundStyle(.secondary).textCase(nil)
      } footer: {
        if tweaks.contains(where: \.inProfile) {
          Footer(L10n.s("Settings with a lock are applied by the RemoveMacAI profile, which macOS asks you to approve.", "带有锁形图标的设置项由 RemoveMacAI 配置描述文件生效，需要您在 macOS 系统设置中批准。"))
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(group.title)
    .toolbar {
      ToolbarItem {
        Menu {
          Button(L10n.s("Select All", "全选")) { for t in tweaks where t.supported { model.toggle(t, true) } }
          Button(L10n.s("Select Recommended", "选择推荐项")) {
            for t in tweaks { model.toggle(t, t.presets.contains(.recommended) || model.state(t) == .applied) }
          }
          Button(L10n.s("Deselect All", "取消全选")) { for t in tweaks { model.toggle(t, false) } }
        } label: {
          Label(L10n.s("Select", "选择"), systemImage: "checklist")
        }
      }
    }
  }
}

struct TweakRow: View {
  @Environment(AppModel.self) private var model
  let tweak: Tweak

  var body: some View {
    let state = model.state(tweak)
    let wanted = model.isOn(tweak)
    Toggle(isOn: Binding(get: { wanted }, set: { model.toggle(tweak, $0) })) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(tweak.title)
          if tweak.inProfile {
            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
              .help(L10n.s("Locked by the RemoveMacAI profile", "由 RemoveMacAI 描述文件锁定"))
          }
          if let note = pendingNote(state: state, wanted: wanted) {
            Text(note).font(.caption.weight(.medium)).foregroundStyle(.tint)
          }
        }
        Text(tweak.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if let caveat = tweak.caveat {
          Label(caveat, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
        if state == .managed {
          Text(L10n.s("Managed by another profile on this Mac.", "由这台 Mac 上的其他配置描述文件管理。")).font(.caption).foregroundStyle(.secondary)
        } else if state == .unsupported {
          Text(L10n.s("Needs macOS \(tweak.since.0).\(tweak.since.1) or newer.", "需要 macOS \(tweak.since.0).\(tweak.since.1) 或更高版本。")).font(.caption).foregroundStyle(.secondary)
        } else if state == .partial {
          Text(L10n.s("Partly applied.", "部分已应用。")).font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 2)
    }
    .toggleStyle(.switch)
    .disabled(state == .managed || state == .unsupported)
  }

  func pendingNote(state: TweakState, wanted: Bool) -> String? {
    if wanted && state != .applied { return L10n.s("Applies on review", "将在应用时生效") }
    if !wanted && state != .notApplied && state != .managed && state != .unsupported { return L10n.s("Undoes on review", "将在应用时撤销") }
    return nil
  }
}

// MARK: - Background items

struct BackgroundView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Form {
      Section {
        if model.background.isEmpty {
          Text(L10n.s("No background items from other apps.", "没有来自其他应用的后台项目。")).foregroundStyle(.secondary)
        }
        ForEach(model.background) { item in
          Toggle(isOn: Binding(
            get: { !model.backgroundOff.contains(item.id) },
            set: { model.setBackground(item, off: !$0) }
          )) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(item.owner)
                if item.system {
                  Text(L10n.s("All users", "全部用户")).font(.caption2.weight(.medium)).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
                }
              }
              Text(item.label).font(.caption.monospaced()).foregroundStyle(.secondary)
              Text(item.program).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
            }
          }
          .toggleStyle(.switch)
          .disabled(model.backgroundBusy)
        }
      } header: {
        Text(L10n.s("Updaters, helpers and agents other apps installed. They run whether or not their app is open. Switching one off takes effect at once.", "其他第三方应用安装的更新程序、辅助工具和代理程序。无论其对应应用是否打开都会在后台运行。关闭某项将立即生效。"))
          .font(.body).foregroundStyle(.secondary).textCase(nil)
      } footer: {
        Footer(L10n.s("Items marked All users ask for your password. Apple's own background services are protected by System Integrity Protection, so RemoveMacAI leaves them alone.", "标有“全部用户”的项目需要输入管理员密码。Apple 系统自有的后台服务受系统完整性保护 (SIP) 机制保护，RemoveMacAI 不会触碰。"))
      }
    }
    .formStyle(.grouped)
    .navigationTitle(L10n.s("Background Items", "后台启动项"))
    .toolbar {
      ToolbarItem {
        Button { model.loadBackground() } label: { Label(L10n.s("Reload", "重新载入"), systemImage: "arrow.clockwise") }
      }
    }
  }
}

// MARK: - Storage

struct StorageView: View {
  @Environment(AppModel.self) private var model
  private var _confirming = SwiftUI.State(initialValue: false)
  private var confirming: Bool {
    get { _confirming.wrappedValue }
    nonmutating set { _confirming.wrappedValue = newValue }
  }
  private var confirmingBinding: SwiftUI.Binding<Bool> { _confirming.projectedValue }

  init() {}

  var body: some View {
    Form {
      if !model.scanned {
        Section {
          HStack(spacing: 14) {
            Image(systemName: "internaldrive").font(.title).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
              Text(L10n.s("Find space you can get back", "查找可释放的存储空间")).font(.headline)
              Text(L10n.s("Looks for old installers, aerial videos, Xcode leftovers, app caches and Time Machine snapshots. Nothing moves until you choose.", "扫描旧安装包、航拍屏幕保护视频、Xcode 缓存、应用缓存及时间机器本地快照。在您手动确认前不会移动或删除任何文件。"))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.scanning { ProgressView().controlSize(.small) } else { Button(L10n.s("Scan", "开始扫描")) { model.scan() } }
          }
          .padding(.vertical, 4)
        }
      } else {
        Section {
          if model.storage.isEmpty {
            Text(L10n.s("Nothing to clean up.", "暂无可清理项目。")).foregroundStyle(.secondary)
          }
          ForEach(model.storage) { item in
            HStack(alignment: .top, spacing: 10) {
              Toggle("", isOn: Binding(
                get: { model.storageChosen.contains(item.id) },
                set: { if $0 { model.storageChosen.insert(item.id) } else { model.storageChosen.remove(item.id) } }
              ))
              .toggleStyle(.checkbox)
              .labelsHidden()
              VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let caveat = item.caveat {
                  Label(caveat, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              Text(item.kind == .snapshots
                ? L10n.s("\(item.count) snapshot\(item.count == 1 ? "" : "s")", "\(item.count) 个快照")
                : Term.size(item.bytes))
                .monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
          }
        } header: {
          HStack {
            Text(L10n.s("Files go to the Trash, so nothing is gone until you empty it.", "文件将移至废纸篓，在清倒废纸篓前均可找回。")).textCase(nil)
            Spacer()
            if model.scanning { ProgressView().controlSize(.small) } else { Button(L10n.s("Scan Again", "重新扫描")) { model.scan() }.buttonStyle(.link) }
          }
        }
        Section {
          HStack {
            if let message = model.cleanMessage {
              Text(message).foregroundStyle(.secondary)
            } else {
              Text(model.storageChosen.isEmpty
                ? L10n.s("Nothing selected", "未选择任何项目")
                : L10n.s("Selected: \(Term.size(model.chosenBytes))", "已选择：\(Term.size(model.chosenBytes))")).monospacedDigit()
            }
            Spacer()
            if model.cleaning { ProgressView().controlSize(.small) }
            Button(L10n.s("Move to Trash…", "移至废纸篓…")) { confirming = true }
              .buttonStyle(.borderedProminent)
              .disabled(model.storageChosen.isEmpty || model.cleaning)
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(L10n.s("Storage", "空间清理"))
    .confirmationDialog(
      L10n.s("Move the selected items to the Trash?", "确认将所选项目移至废纸篓？"), isPresented: confirmingBinding
    ) {
      Button(L10n.s("Move to Trash", "移至废纸篓")) { model.clean() }
    } message: {
      Text(L10n.s("About \(Term.size(model.chosenBytes)). Items only an administrator can move ask for your password.", "预计占用约 \(Term.size(model.chosenBytes))。需要管理员权限的项目将提示输入密码。"))
    }
  }
}

// MARK: - Undo

struct ChangesView: View {
  @Environment(AppModel.self) private var model
  private var _confirming = SwiftUI.State(initialValue: false)
  private var confirming: Bool {
    get { _confirming.wrappedValue }
    nonmutating set { _confirming.wrappedValue = newValue }
  }
  private var confirmingBinding: SwiftUI.Binding<Bool> { _confirming.projectedValue }

  init() {}

  var body: some View {
    Form {
      Section(L10n.s("Profile", "配置描述文件")) {
        if model.snapshot.profile.on {
          LabeledContent(L10n.s("RemoveMacAI profile", "RemoveMacAI 描述文件"), value: L10n.s("Installed", "已安装"))
          if model.currentAI != nil { Label(L10n.s("Apple Intelligence off", "Apple Intelligence 已关闭"), systemImage: "apple.intelligence") }
          ForEach(model.snapshot.profile.tweaks.sorted(), id: \.self) { id in
            Label(Tweaks.tweak(id)?.title ?? id, systemImage: "lock.fill")
          }
        } else {
          Text(L10n.s("Not installed.", "未安装。")).foregroundStyle(.secondary)
        }
      }
      Section(L10n.s("Other changes", "其他更改记录")) {
        let entries = model.journal.entries.sorted { $0.value.date > $1.value.date }
        if entries.isEmpty {
          Text(L10n.s("None.", "无。")).foregroundStyle(.secondary)
        }
        ForEach(entries, id: \.key) { key, entry in
          LabeledContent {
            Text(entry.date, style: .date).foregroundStyle(.secondary)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(title(entry.tweak))
              Text(key).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
          }
        }
      }
      Section {
        HStack {
          Text(L10n.s("Puts every setting back as it was before RemoveMacAI changed it, and removes the profile.", "将 RemoveMacAI 修改的所有设置还原至初始状态，并移除配置描述文件。"))
            .foregroundStyle(.secondary)
          Spacer()
          Button(L10n.s("Undo Everything…", "全部撤销还原…"), role: .destructive) { confirming = true }
            .disabled(!model.snapshot.profile.on && model.journal.entries.isEmpty)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(L10n.s("Undo", "更改与还原"))
    .confirmationDialog(L10n.s("Undo everything RemoveMacAI changed?", "确定要还原 RemoveMacAI 的所有更改吗？"), isPresented: confirmingBinding) {
      Button(L10n.s("Undo Everything", "全部撤销还原"), role: .destructive) { model.undoEverything() }
    } message: {
      Text(L10n.s("macOS asks you to remove the profile in System Settings. Deleted models download again when a feature needs them, and files in the Trash stay there.", "macOS 会提示您在“系统设置”中移除描述文件。已删除的模型在系统特性需要时会重新下载，已移至废纸篓的文件将保留在废纸篓中。"))
    }
  }

  func title(_ id: String) -> String {
    if let t = Tweaks.tweak(id) { return t.title }
    if let item = model.background.first(where: { $0.id == id }) { return L10n.s("Background item: \(item.owner)", "后台项目：\(item.owner)") }
    return id
  }
}

struct Footer: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}
