import Foundation

var usageEN: String {
  """
  RemoveMacAI \(version)
  Debloats macOS: turns Apple Intelligence off, deletes its models, and turns
  off analytics, ads and the rest. Every change can be undone.

  Apple Intelligence
    removemacai                 show what is on, then turn it off (asks first)
    removemacai status          show what is on and how much space the models take
    removemacai off [options]   turn it off without the overview
        --keep a,b              leave these features on (names: removemacai features)
        --dry-run               show what would change, change nothing
        --yes                   do not ask
    removemacai on              turn Apple Intelligence back on, keep the other tweaks
    removemacai features        list the feature names

  Debloat
    removemacai tweaks [--json]           list every tweak and whether it is applied
    removemacai apply <names> [options]   apply tweaks
        --preset recommended|privacy      apply a preset, Apple Intelligence off included
        --dry-run, --yes
    removemacai undo <names>              undo tweaks
    removemacai background [off|on <labels>]
                                          other apps' background items
    removemacai clean [<names>]           show space to get back, move some to the Trash
    removemacai export <file.mobileconfig> [--preset p] [<names>] [--keep a,b] [--no-ai]
                                          write the profile for an MDM

    removemacai revert          undo everything RemoveMacAI changed
    removemacai app             open the RemoveMacAI app

  """
}

var usageZH: String {
  """
  RemoveMacAI \(version)
  macOS 系统去臃肿与优化：彻底关闭 Apple Intelligence 并清理模型，
  禁用系统分析与广告，精简弹窗与冗余项。所有更改均可完全撤销。

  Apple Intelligence (人工智能)
    removemacai                 显示当前状态并确认关闭 (需确认)
    removemacai status          查看各特性状态与本地模型磁盘占用
    removemacai off [选项]       直接关闭 Apple Intelligence
        --keep a,b              保持指定特性开启 (列表见: removemacai features)
        --dry-run               演练模式，仅展示拟修改项，不作实际更改
        --yes                   自动确认，跳过交互提示
    removemacai on              重新开启 Apple Intelligence，保留其他优化
    removemacai features        列出所有受支持的 AI 功能名称

  Debloat (系统瘦身与优化)
    removemacai tweaks [--json]           列出所有可调整项及当前状态
    removemacai apply <名称> [选项]       应用指定的优化项
        --preset recommended|privacy      应用预设方案（包含彻底关闭 Apple Intelligence）
        --dry-run, --yes
    removemacai undo <名称>               还原指定的优化项
    removemacai background [off|on <标签>]
                                          管理第三方应用的后台开机自启项
    removemacai clean [<名称>]            检查可释放的存储空间，将指定项移至废纸篓
    removemacai export <配置文件.mobileconfig> [--preset p] [<名称>] [--keep a,b] [--no-ai]
                                          导出供 MDM 批量部署使用的配置描述文件

    removemacai revert          完全还原 RemoveMacAI 作出的所有修改
    removemacai app             启动 RemoveMacAI 图形界面应用程序

  """
}

var usage: String { L10n.isChinese ? usageZH : usageEN }

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
  guard let i = args.firstIndex(of: name) else { return false }
  args.remove(at: i)
  return true
}
func option(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  let value = args[i + 1]
  args.removeSubrange(i...(i + 1))
  return value
}
func presetOption() -> Preset? {
  guard let name = option("--preset") else { return nil }
  guard let preset = Preset(rawValue: name) else {
    Term.fail(L10n.s("there is no preset called \"\(name)\". Use recommended or privacy", "不存在名为 \"\(name)\" 的预设。请使用 recommended 或 privacy"))
  }
  return preset
}

// Opened from Finder: the app. With arguments, or from a bare binary: the CLI.
if args.isEmpty && Bundle.main.bundleURL.pathExtension == "app" || args.first == "app" {
  guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
    Term.fail(L10n.s("RemoveMacAI needs macOS 26 or newer", "RemoveMacAI 需要 macOS 26 或更高版本"))
  }
  Shell.inApp = true
  RemoveMacAIApp.main()
  exit(0)
}

guard args.first == "selftest" || ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
  Term.fail(L10n.s("RemoveMacAI needs macOS 26 or newer", "RemoveMacAI 需要 macOS 26 或更高版本"))
}

switch args.first {
case "status":
  Commands.status()
case "off", nil:
  if !args.isEmpty { args.removeFirst() }
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let extra = args.first { Term.fail("unknown option \(extra)") }
  exit(Commands.off(keep: keep, dryRun: dryRun, yes: yes) ? 0 : 1)
case "revert":
  Commands.revert()
case "on":
  Commands.on()
case "features":
  Commands.features()
case "tweaks":
  args.removeFirst()
  TweakCommands.list(json: flag("--json"))
case "apply", "undo":
  let command = args.removeFirst()
  let preset = presetOption()
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let bad = args.first(where: { $0.hasPrefix("-") }) { Term.fail("unknown option \(bad)") }
  let ok = command == "apply"
    ? TweakCommands.apply(ids: args, preset: preset, dryRun: dryRun, yes: yes)
    : TweakCommands.undo(ids: args, dryRun: dryRun, yes: yes)
  exit(ok ? 0 : 1)
case "background":
  args.removeFirst()
  let yes = flag("--yes") || flag("-y")
  exit(TweakCommands.background(args, yes: yes) ? 0 : 1)
case "clean":
  args.removeFirst()
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  exit(TweakCommands.clean(ids: args, dryRun: dryRun, yes: yes) ? 0 : 1)
case "export":
  args.removeFirst()
  let preset = presetOption()
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty })
  let noAI = flag("--no-ai")
  guard let path = args.first else { Term.fail("name the file to write, for example: removemacai export RemoveMacAI.mobileconfig") }
  TweakCommands.export(path: path, ids: Array(args.dropFirst()), preset: preset, keepAI: keep, noAI: noAI)
case "selftest":
  exit(selfTest() ? 0 : 1)
case "--version", "-v", "version":
  print(version)
case "help", "--help", "-h":
  print(usage, terminator: "")
default:
  print(usage, terminator: "")
  exit(1)
}
