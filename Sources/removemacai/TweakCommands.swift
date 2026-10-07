import Foundation

/// The debloater commands: tweaks, presets, background items, storage and export.
enum TweakCommands {
  static func label(_ state: TweakState) -> String {
    switch state {
    case .applied: return Term.green(L10n.s("done", "已应用"))
    case .notApplied: return Term.dim(L10n.s("not applied", "未应用"))
    case .partial: return Term.yellow(L10n.s("partly", "部分应用"))
    case .managed: return Term.yellow(L10n.s("managed by another profile", "由其他描述文件托管"))
    case .unsupported: return Term.dim(L10n.s("needs a newer macOS", "需要更高版本 macOS"))
    }
  }

  // MARK: tweaks

  static func list(json: Bool) {
    let s = Snapshot()
    if json {
      let rows = Tweaks.all.map { t -> [String: Any] in
        ["id": t.id, "group": t.group.rawValue, "title": t.title, "state": "\(s.state(t))",
         "profile": t.inProfile, "presets": t.presets.map(\.rawValue).sorted()]
      }
      let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
      print(String(decoding: data, as: UTF8.self))
      return
    }
    Commands.header()
    for group in TweakGroup.allCases {
      print(Term.bold(group.title))
      for t in Tweaks.all where t.group == group {
        print("  " + Term.pad(t.id, 22) + Term.pad(t.title, 46) + label(s.state(t)))
      }
      print()
    }
    print(Term.dim(L10n.s("Apply some with: removemacai apply <names>   or a preset: removemacai apply --preset recommended", "应用指定项目：removemacai apply <名称>   或应用预设：removemacai apply --preset recommended")))
  }

  // MARK: apply and undo

  /// Applies the named tweaks (and, for a preset, turns Apple Intelligence off),
  /// leaving everything else as it is.
  static func apply(ids: [String], preset: Preset?, dryRun: Bool, yes: Bool) -> Bool {
    let s = Snapshot()
    var requested = Set<String>()
    for id in ids {
      guard let tweak = Tweaks.tweak(id) else {
        Term.fail(L10n.s("there is no tweak called \"\(id)\". The names are listed by: removemacai tweaks", "不存在名为 \"\(id)\" 的优化项。可用名称请运行：removemacai tweaks"))
      }
      requested.insert(tweak.id)
    }
    if let preset { requested.formUnion(Tweaks.preset(preset).map(\.id)) }
    guard !requested.isEmpty else { Term.fail(L10n.s("name the tweaks to apply, or a preset with --preset", "请指定要应用的优化项，或使用 --preset 指定预设")) }
    let currentAI: Set<String>? = s.profile.ai && s.profile.on ? s.profile.kept : nil
    let ai: Set<String>? = preset != nil ? (currentAI ?? []) : currentAI
    let plan = Plan.make(wanted: s.appliedTweaks.union(requested), ai: ai, snapshot: s)
    return run(plan, dryRun: dryRun, yes: yes, verb: "Apply")
  }

  static func undo(ids: [String], dryRun: Bool, yes: Bool) -> Bool {
    let s = Snapshot()
    var wanted = s.appliedTweaks
    for id in ids {
      guard Tweaks.tweak(id) != nil else { Term.fail(L10n.s("there is no tweak called \"\(id)\"", "不存在名为 \"\(id)\" 的优化项")) }
      wanted.remove(id)
    }
    let ai: Set<String>? = s.profile.on && s.profile.ai ? s.profile.kept : nil
    let plan = Plan.make(wanted: wanted, ai: ai, snapshot: s)
    return run(plan, dryRun: dryRun, yes: yes, verb: "Undo")
  }

  static func describe(_ plan: Plan) {
    if !plan.apply.isEmpty {
      print(Term.bold(L10n.s("Apply", "拟应用")))
      for t in plan.apply {
        print("  " + Term.green("+") + " " + t.title)
        for c in t.changes { print("      " + Term.dim(c.command)) }
        if let caveat = t.caveat { print("      " + Term.yellow(caveat)) }
      }
    }
    if !plan.revert.isEmpty {
      print(Term.bold(L10n.s("Undo", "拟还原")))
      for t in plan.revert { print("  " + Term.yellow("-") + " " + t.title) }
    }
    if let profile = plan.profile {
      print(Term.bold(L10n.s("Profile", "描述文件")))
      print("  " + (profile.isEmpty ? L10n.s("remove the RemoveMacAI profile", "移除 RemoveMacAI 描述文件") : L10n.s("install the updated profile (macOS asks you to approve it in System Settings)", "安装更新的描述文件（macOS 提示需在系统设置中批准确认）")))
    }
    if !plan.models.isEmpty {
      print(Term.bold(L10n.s("Models", "本地模型")))
      for name in plan.models { print("  " + L10n.s("delete ", "删除 ") + (Catalog.modelSet(name)?.title ?? name)) }
    }
    print()
  }

  static func run(_ plan: Plan, dryRun: Bool, yes: Bool, verb: String) -> Bool {
    Commands.header()
    guard !plan.isEmpty else {
      print(Term.green(L10n.s("Nothing to change.", "无需更改。")) + L10n.s(" Everything named is already that way.", " 所有指定项目已处于目标状态。"))
      return true
    }
    describe(plan)
    if dryRun {
      print(Term.bold(L10n.s("Dry run, nothing changed.", "演练模式 (Dry run)，未作任何更改。")))
      return true
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      guard Term.ask(L10n.s("\(verb) these changes?", "确认\(verb == "Apply" ? "应用" : "撤销")这些更改？")) else {
        print(L10n.s("Nothing changed.", "未作任何更改。"))
        return true
      }
      print()
    }
    let problems = Engine.runLocal(plan)
    for p in problems { print("  " + Term.yellow("!") + " " + p) }
    if !(plan.apply + plan.revert).filter({ !$0.inProfile }).isEmpty {
      print(Term.green("✓") + L10n.s(" Settings changed", " 设置已更新"))
    }
    var ok = problems.isEmpty
    if let profile = plan.profile {
      ok = (profile.isEmpty ? Commands.removeProfile() : Commands.installProfile(profile)) && ok
    }
    if ok && !plan.models.isEmpty {
      ok = Commands.deleteModels(plan.models, step: L10n.s("Models", "本地模型"))
    }
    print()
    print((ok ? Term.green(L10n.s("Done.", "已完成。")) : Term.yellow(L10n.s("Incomplete.", "未完全完成。"))) + Term.dim(L10n.s("  Undo everything with: \(Commands.undo)", "  完全还原所有更改：\(Commands.undo)")))
    return ok
  }

  // MARK: background items

  static func background(_ args: [String], yes: Bool) -> Bool {
    let items = BackgroundItems.scan()
    let labels = BackgroundItems.disabledLabels()
    guard let action = args.first, action == "off" || action == "on" else {
      Commands.header()
      if items.isEmpty {
        print(L10n.s("No background items from other apps.", "暂无第三方应用的后台启动项。"))
        return true
      }
      print(Term.bold(L10n.s("Background items from other apps", "第三方应用的后台启动项")))
      for item in items {
        let state = BackgroundItems.isDisabled(item, labels) ? Term.dim(L10n.s("off", "已关闭")) : Term.green(L10n.s("on", "开启中"))
        print("  " + Term.pad(item.label, 48) + Term.pad(item.owner, 22) + state + (item.system ? Term.dim(L10n.s("  (all users)", "  (所有用户)")) : ""))
      }
      print()
      print(Term.dim(L10n.s("Turn one off with: removemacai background off <label>", "禁用指定项命令：removemacai background off <标签>")))
      return true
    }
    let names = Set(args.dropFirst())
    let chosen = items.filter { names.contains($0.label) }
    for name in names where !chosen.contains(where: { $0.label == name }) {
      Term.fail(L10n.s("there is no background item called \"\(name)\"", "不存在名为 \"\(name)\" 的后台启动项"))
    }
    guard !chosen.isEmpty else { Term.fail(L10n.s("name the items, as listed by: removemacai background", "请指定项目名称，列表可运行：removemacai background")) }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      let verb = action == "off" ? L10n.s("Turn off", "关闭") : L10n.s("Turn on", "开启")
      guard Term.ask("\(verb) \(chosen.map(\.label).joined(separator: ", "))?") else {
        print(L10n.s("Nothing changed.", "未作任何更改。"))
        return true
      }
    }
    let problems = BackgroundItems.set(chosen, disabled: action == "off")
    for p in problems { print(Term.yellow("!") + " " + p) }
    if problems.isEmpty { print(Term.green("✓") + " " + (action == "off" ? L10n.s("Turned off", "已关闭") : L10n.s("Turned on", "已开启")) + ": " + chosen.map(\.label).joined(separator: ", ")) }
    return problems.isEmpty
  }

  // MARK: storage

  static func clean(ids: [String], dryRun: Bool, yes: Bool) -> Bool {
    Commands.header()
    print(Term.dim(L10n.s("Measuring...", "正在测量空间占用...")))
    let items = Storage.scan()
    if Term.color { print("\u{1B}[1A\u{1B}[K", terminator: "") }
    if items.isEmpty {
      print(L10n.s("Nothing to clean.", "暂无可清理项目。"))
      return true
    }
    print(Term.bold(L10n.s("Space you can get back", "可清理释放的存储空间")))
    for item in items {
      let amount = item.kind == .snapshots ? "\(item.count) " + L10n.s("snapshots", "个快照") : Term.size(item.bytes)
      print("  " + Term.pad(item.id, 16) + Term.pad(item.title, 34) + amount)
      if let caveat = item.caveat { print("    " + Term.dim(caveat)) }
    }
    print()
    guard !ids.isEmpty else {
      print(Term.dim(L10n.s("Move some to the Trash with: removemacai clean <names>", "移至废纸篓请执行：removemacai clean <名称>")))
      return true
    }
    let chosen = items.filter { ids.contains($0.id) }
    for id in ids where !chosen.contains(where: { $0.id == id }) {
      Term.fail(L10n.s("\"\(id)\" is not in the list above", "\"\(id)\" 不在上方列表中"))
    }
    let total = chosen.reduce(Int64(0)) { $0 + $1.bytes }
    if dryRun {
      print(Term.bold(L10n.s("Dry run, nothing moved.", "演练模式，未移动任何文件。")) + L10n.s(" It would free about ", " 将可释放约 ") + Term.size(total) + "。")
      return true
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      guard Term.ask(L10n.s("Move \(chosen.map(\.title).joined(separator: ", ")) to the Trash?", "确定将 \(chosen.map(\.title).joined(separator: "、")) 移至废纸篓吗？")) else {
        print(L10n.s("Nothing moved.", "未移动任何文件。"))
        return true
      }
    }
    let result = Storage.clean(chosen)
    for p in result.problems { print(Term.yellow("!") + " " + p) }
    print(Term.green("✓") + L10n.s(" Moved to the Trash. Empty the Trash to free about \(Term.size(total)).", " 已移至废纸篓。清倒废纸篓即可释放约 \(Term.size(total)) 空间。"))
    if result.protected > 0 { print(Term.dim(L10n.s("  \(result.protected) item(s) macOS protects stayed where they were.", "  受系统完整性保护的 \(result.protected) 个项目已保留。"))) }
    return result.problems.isEmpty
  }

  // MARK: export

  /// Writes the profile for a preset or named tweaks, for deploying with an MDM.
  static func export(path: String, ids: [String], preset: Preset?, keepAI: Set<String>, noAI: Bool) {
    var tweaks = Set<String>()
    for id in ids {
      guard let t = Tweaks.tweak(id) else { Term.fail("there is no tweak called \"\(id)\"") }
      guard t.inProfile else { Term.fail("\(id) is a per-user setting, so it can't go in a profile") }
      tweaks.insert(id)
    }
    if let preset { tweaks.formUnion(Tweaks.preset(preset).filter(\.inProfile).map(\.id)) }
    let contents = Profile.Contents(ai: noAI ? nil : keepAI, tweaks: tweaks)
    do {
      try Profile.data(contents).write(to: URL(fileURLWithPath: path))
    } catch { Term.fail("could not write \(path): \(error)") }
    print(Term.green("✓") + " Wrote \(path)")
    print(Term.dim("  Apple Intelligence: \(noAI ? "left alone" : keepAI.isEmpty ? "off" : "off except \(keepAI.sorted().joined(separator: ", "))")"))
    print(Term.dim("  Tweaks: \(tweaks.isEmpty ? "none" : tweaks.sorted().joined(separator: ", "))"))
    print(Term.dim("  Per-user tweaks (Finder, Dock, typing) aren't in profiles; run removemacai on each Mac for those."))
  }
}
