import SwiftUI

struct ContentView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      Sidebar()
        .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    } detail: {
      DetailView(page: model.page ?? .overview)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if model.pendingCount > 0 { PendingBar() }
        }
    }
    .sheet(isPresented: $model.reviewing) { ReviewSheet() }
    .sheet(isPresented: Binding(get: { model.run != nil }, set: { if !$0 { model.dismissRun() } })) {
      RunSheet()
    }
  }
}

struct DetailView: View {
  let page: Page

  var body: some View {
    switch page {
    case .overview: OverviewView()
    case .intelligence: IntelligenceView()
    case .group(let group): TweakGroupView(group: group)
    case .background: BackgroundView()
    case .storage: StorageView()
    case .changes: ChangesView()
    }
  }
}

// MARK: - Sidebar

struct Sidebar: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    List(selection: $model.page) {
      row(.overview, badge: 0)
      Section(L10n.s("Debloat", "系统优化")) {
        row(.intelligence, badge: model.aiPending ? 1 : 0)
        ForEach(TweakGroup.allCases) { group in
          row(.group(group), badge: model.pending(in: group))
        }
        row(.background, badge: 0)
      }
      Section(L10n.s("Clean Up", "清理维护")) {
        row(.storage, badge: 0)
        row(.changes, badge: 0)
      }
    }
    .listStyle(.sidebar)
  }

  func row(_ page: Page, badge: Int) -> some View {
    Label(page.title, systemImage: page.symbol)
      .badge(badge)
      .tag(page)
  }
}

// MARK: - Bottom bar and review

struct PendingBar: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.tint)
      Text(L10n.s(
        model.pendingCount == 1 ? "1 change to apply" : "\(model.pendingCount) changes to apply",
        "\(model.pendingCount) 项待生效的更改"
      ))
      .font(.callout.weight(.medium))
      Spacer()
      Button(L10n.s("Discard", "放弃")) { model.discard() }
      Button(L10n.s("Review and Apply…", "审核并应用…")) { model.reviewing = true }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }
}

struct ReviewSheet: View {
  @Environment(AppModel.self) private var model
  private var _plan = SwiftUI.State<Plan?>(initialValue: nil)
  private var plan: Plan? {
    get { _plan.wrappedValue }
    nonmutating set { _plan.wrappedValue = newValue }
  }

  init() {}

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.s("Review changes", "审核更改")).font(.title2.weight(.semibold))
        Text(L10n.s("Nothing changes until you click Apply. Everything here can be undone later.", "在点击“应用”之前不会修改任何设置。此处的所有更改后续均可撤销。"))
          .foregroundStyle(.secondary)
      }
      .padding(20)
      Divider()
      if let plan {
        List {
          if !plan.apply.isEmpty {
            Section(L10n.s("Apply", "应用")) {
              ForEach(plan.apply) { t in ChangeRow(tweak: t, adding: true) }
            }
          }
          if !plan.revert.isEmpty {
            Section(L10n.s("Undo", "还原")) {
              ForEach(plan.revert) { t in ChangeRow(tweak: t, adding: false) }
            }
          }
          if model.aiPending || !plan.models.isEmpty {
            Section("Apple Intelligence") {
              if model.aiPending, let kept = model.targetAI {
                Label(
                  L10n.s(
                    kept.isEmpty ? "Turn off every feature" : "Turn off everything except \(kept.count) kept feature\(kept.count == 1 ? "" : "s")",
                    kept.isEmpty ? "关闭所有特性" : "关闭除 \(kept.count) 项保留特性外的所有功能"
                  ),
                  systemImage: "apple.intelligence")
              } else if model.aiPending {
                Label(
                  L10n.s(
                    "Turn Apple Intelligence back on. macOS downloads its models again when a feature needs them.",
                    "重新开启 Apple Intelligence。macOS 会在特性需要时重新下载对应模型。"
                  ),
                  systemImage: "arrow.uturn.backward")
              }
              if !plan.models.isEmpty {
                Label(
                  L10n.s(
                    model.modelTotal > 0
                      ? "Delete the models, about \(Term.size(model.modelTotal))"
                      : "Ask macOS to finish removing leftover model files",
                    model.modelTotal > 0
                      ? "删除模型文件，预计释放 \(Term.size(model.modelTotal))"
                      : "请求 macOS 完成残留模型文件的清理"
                  ),
                  systemImage: "trash")
              }
            }
          }
          if let profile = plan.profile {
            Section(L10n.s("Approval", "授权确认")) {
              Label(
                L10n.s(
                  profile.isEmpty
                    ? "Remove the RemoveMacAI profile in System Settings."
                    : "Approve the RemoveMacAI profile in System Settings. macOS asks for this click. The locked settings change once you do.",
                  profile.isEmpty
                    ? "在“系统设置”中移除 RemoveMacAI 描述文件。"
                    : "在“系统设置”中批准 RemoveMacAI 描述文件。macOS 会提示确认此操作，批准后受保护的设置项即可生效。"
                ),
                systemImage: "checkmark.shield")
            }
          }
        }
        .listStyle(.inset)
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      HStack {
        Spacer()
        Button(L10n.s("Cancel", "取消"), role: .cancel) { model.reviewing = false }
          .keyboardShortcut(.cancelAction)
        Button(L10n.s("Apply", "应用")) { model.apply() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(plan?.isEmpty ?? true)
      }
      .padding(16)
    }
    .frame(width: 600, height: 560)
    .task {
      let wanted = model.wanted
      let ai = model.targetAI
      let snapshot = model.snapshot
      plan = await Task.detached { Plan.make(wanted: wanted, ai: ai, snapshot: snapshot) }.value
    }
  }
}

struct ChangeRow: View {
  let tweak: Tweak
  let adding: Bool
  private var _expanded = SwiftUI.State(initialValue: false)
  private var expandedBinding: SwiftUI.Binding<Bool> { _expanded.projectedValue }

  init(tweak: Tweak, adding: Bool) {
    self.tweak = tweak
    self.adding = adding
  }

  var body: some View {
    DisclosureGroup(isExpanded: expandedBinding) {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(tweak.changes.indices, id: \.self) { i in
          Text(tweak.changes[i].command)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      .padding(.vertical, 4)
    } label: {
      HStack {
        Image(systemName: adding ? "plus.circle.fill" : "arrow.uturn.backward.circle.fill")
          .foregroundStyle(adding ? Color.accentColor : .orange)
        Text(tweak.title)
        if tweak.inProfile {
          Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            .help(L10n.s("Locked by the RemoveMacAI profile", "由 RemoveMacAI 描述文件锁定"))
        }
      }
    }
  }
}

// MARK: - Running

struct RunSheet: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 18) {
      switch model.run {
      case .working(let text)?:
        ProgressView().controlSize(.large)
        Text(text).font(.headline)
      case .approveProfile(let remove)?:
        Image(systemName: "checkmark.shield").font(.system(size: 44)).foregroundStyle(.tint)
        Text(L10n.s(
          remove ? "Remove the profile in System Settings" : "Approve the profile in System Settings",
          remove ? "在“系统设置”中移除描述文件" : "在“系统设置”中批准描述文件"
        ))
        .font(.title3.weight(.semibold))
        VStack(alignment: .leading, spacing: 8) {
          if remove {
            step(1, L10n.s("In Device Management, select RemoveMacAI.", "在“通用”>“设备管理”中，选择 RemoveMacAI。"))
            step(2, L10n.s("Click the minus button or Remove, then enter your password.", "点击减号按钮或“移除”，然后输入您的开机密码。"))
          } else {
            step(1, L10n.s("Under Downloaded, double-click RemoveMacAI.", "在“已下载”列表中，双击 RemoveMacAI。"))
            step(2, L10n.s("Click Install, then enter your password.", "点击“安装”，然后输入您的开机密码。"))
          }
        }
        .frame(maxWidth: 360, alignment: .leading)
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(L10n.s("Waiting for System Settings…", "等待“系统设置”操作完成…")).foregroundStyle(.secondary)
        }
        Text(L10n.s(
          "If System Settings says the profile couldn't be installed, click Cancel and report it on GitHub.",
          "如果“系统设置”提示无法安装描述文件，请点击“取消”并在 GitHub 上提交反馈。"
        ))
        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 340)
        HStack {
          Button(L10n.s("Cancel", "取消")) { model.cancel() }
          Button(L10n.s("Open System Settings", "打开系统设置")) { Commands.openProfileSettings() }
            .buttonStyle(.borderedProminent)
        }
      case .finished(let problems, let freed)?:
        Image(systemName: problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .font(.system(size: 44))
          .foregroundStyle(problems.isEmpty ? Color.green : Color.orange)
        Text(L10n.s(problems.isEmpty ? "Done" : "Finished with problems", problems.isEmpty ? "操作已完成" : "完成但存在问题")).font(.title3.weight(.semibold))
        if let freed, freed > 0 {
          Text(L10n.s(
            "Deleted \(Term.size(freed)) of models. macOS removes the files on its own schedule, so Storage settings can count them for a while.",
            "已删除 \(Term.size(freed)) 模型文件。macOS 会按自身计划回收文件，因此“存储空间”设置在一段时间内可能仍显示该占用。"
          ))
          .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
        }
        if !problems.isEmpty {
          ScrollView {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(problems, id: \.self) { Text("• " + $0).textSelection(.enabled) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxWidth: 420, maxHeight: 160)
        }
        Button(L10n.s("Done", "完成")) { model.dismissRun() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      case nil:
        EmptyView()
      }
    }
    .padding(28)
    .frame(width: 460)
    .interactiveDismissDisabled()
  }

  func step(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("\(n)").font(.callout.weight(.semibold).monospacedDigit())
        .frame(width: 22, height: 22)
        .background(Circle().fill(.quaternary))
      Text(text)
    }
  }
}
