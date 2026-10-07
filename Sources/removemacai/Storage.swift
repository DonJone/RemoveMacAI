import Foundation

/// Space RemoveMacAI can give back. Files go to the Trash, so nothing is
/// gone until the Trash is emptied.
struct StorageItem: Identifiable {
  enum Kind {
    /// Files and folders moved to the Trash.
    case files
    /// Unavailable simulators, deleted by simctl.
    case simulators
    /// Time Machine local snapshots, deleted by tmutil.
    case snapshots
  }

  let id: String
  let title: String
  let detail: String
  var caveat: String? = nil
  var kind: Kind = .files
  /// What it would remove right now.
  var paths: [String] = []
  var bytes: Int64 = 0
  var count: Int = 0
}

enum Storage {
  static let home = FileManager.default.homeDirectoryForCurrentUser.path

  /// Optional Apple apps that come with some Macs and reinstall free from the App Store.
  static let appleApps: [(id: String, app: String, extra: [String])] = [
    ("garageband", "GarageBand", [
      "/Library/Application Support/GarageBand", "/Library/Application Support/Logic",
      "/Library/Audio/Apple Loops/Apple",
    ]),
    ("imovie", "iMovie", []),
    ("keynote", "Keynote", []),
    ("numbers", "Numbers", []),
    ("pages", "Pages", []),
  ]

  /// Finds what can go and how big it is. Slow on big caches; call it off the main thread.
  static func scan() -> [StorageItem] {
    var items: [StorageItem] = []

    let wallpaper = home + "/Library/Application Support/com.apple.wallpaper"
    let aerialsInUse = plistText(wallpaper + "/Store/Index.plist").contains("aerial")
    items.append(files(
      id: "aerials",
      title: L10n.s("Aerial wallpaper videos", "动态航拍墙纸与屏保视频"),
      detail: L10n.s("Videos for the moving aerial wallpapers and screen savers. macOS downloads one again when you choose it.", "动态航拍墙纸和屏幕保护程序视频。若重新在系统设置中选中，macOS 将按需重新下载。"),
      caveat: aerialsInUse ? L10n.s("You use an aerial wallpaper or screen saver now, so macOS will download it again.", "当前正在使用航拍动态墙纸或屏保，清理后系统可能会重新触发下载。") : nil,
      paths: children(wallpaper + "/aerials/videos")
        + children("/Library/Application Support/com.apple.idleassetsd/Customer")))

    items.append(files(
      id: "installers",
      title: L10n.s("macOS installers", "macOS 安装器安装包"),
      detail: L10n.s("Old \"Install macOS\" apps left in Applications after an upgrade.", "系统升级后残留在“应用程序”目录下的“安装 macOS”旧安装程序。"),
      paths: children("/Applications").filter {
        let name = ($0 as NSString).lastPathComponent
        return name.hasPrefix("Install macOS") && name.hasSuffix(".app")
      }))

    items.append(files(
      id: "ios-firmware",
      title: L10n.s("iPhone and iPad updates", "iPhone 与 iPad 固件升级包"),
      detail: L10n.s("Software update files Finder downloaded for iPhones and iPads. They download again when needed.", "访达下载的 iOS / iPadOS 固件恢复与更新文件（IPSW），必要时会自动重新下载。"),
      paths: children(home + "/Library/iTunes/iPhone Software Updates")
        + children(home + "/Library/iTunes/iPad Software Updates")))

    let xcode = home + "/Library/Developer/Xcode"
    items.append(files(
      id: "derived-data",
      title: L10n.s("Xcode build data", "Xcode 编译构建缓存 (DerivedData)"),
      detail: L10n.s("Xcode's DerivedData folder. Xcode rebuilds it on the next build.", "Xcode 的 DerivedData 缓存目录。下次在 Xcode 构建项目时会自动重建。"),
      paths: children(xcode + "/DerivedData")))
    items.append(files(
      id: "device-support",
      title: L10n.s("Xcode device support", "Xcode 真机调试符号文件"),
      detail: L10n.s("Debug symbols Xcode copied from each iPhone, iPad and Watch you connected. They copy again on the next connection.", "Xcode 从连接过的每台 iPhone、iPad 和 Apple Watch 拷贝的调试符号，再次连接时会自动同步。"),
      paths: ["iOS", "watchOS", "tvOS", "visionOS"].flatMap { children(xcode + "/\($0) DeviceSupport") }))

    var simulators = StorageItem(
      id: "simulators",
      title: L10n.s("Unavailable simulators", "不可用的废弃模拟器运行时"),
      detail: L10n.s("Simulators for runtimes that are no longer installed, so they can't run.", "对应 SDK 运行时已卸载或失效的模拟器数据，已无法正常运行。"),
      kind: .simulators)
    let unavailable = unavailableSimulators()
    simulators.paths = unavailable
    simulators.count = unavailable.count
    simulators.bytes = unavailable.reduce(0) { $0 + size($1) }
    items.append(simulators)

    items.append(files(
      id: "caches",
      title: L10n.s("App caches", "第三方应用程序缓存"),
      detail: L10n.s("Files apps keep to load faster. Apps rebuild them, so the first launch afterwards can be slower.", "各应用程序为加快加载所生成的缓存。清理后应用会在下次启动时自动重新生成。"),
      caveat: L10n.s("Quit your apps first. Apple's own caches are left alone.", "建议清理前先退出相关应用。系统原生应用的核心缓存不会被改动。"),
      paths: children(home + "/Library/Caches").filter { !($0 as NSString).lastPathComponent.hasPrefix("com.apple.") }))

    for app in appleApps {
      let path = "/Applications/\(app.app).app"
      guard FileManager.default.fileExists(atPath: path) else { continue }
      items.append(files(
        id: app.id, title: app.app,
        detail: L10n.s("One of Apple's optional apps. It reinstalls free from the App Store.", "Apple 可选预装应用，日后可随时在 App Store 免费重新下载安装。"),
        paths: [path] + app.extra.filter { FileManager.default.fileExists(atPath: $0) }))
    }

    var snapshots = StorageItem(
      id: "snapshots",
      title: L10n.s("Time Machine local snapshots", "时间机器本地快照"),
      detail: L10n.s("Hourly copies Time Machine keeps on this disk between backups. macOS counts them as System Data.", "时间机器在未连接外置备份盘时保存在本地磁盘上的每小时快照（在系统中计入“系统数据”）。"),
      caveat: L10n.s("Your backups on the backup disk aren't touched.", "外置备份磁盘中的历史备份文件不会受到任何影响。"),
      kind: .snapshots)
    snapshots.paths = localSnapshotDates()
    snapshots.count = snapshots.paths.count
    items.append(snapshots)

    return items.filter { $0.kind == .files ? $0.bytes > 0 : !$0.paths.isEmpty }
  }

  static func files(id: String, title: String, detail: String, caveat: String? = nil, paths: [String]) -> StorageItem {
    // Folders macOS won't let us read measure 0; they can't be moved either, so leave them out.
    let sized = paths.map { ($0, size($0)) }.filter { $0.1 > 0 }
    var item = StorageItem(id: id, title: title, detail: detail, caveat: caveat, paths: sized.map(\.0))
    item.count = sized.count
    item.bytes = sized.reduce(0) { $0 + $1.1 }
    return item
  }

  static func plistText(_ path: String) -> String {
    guard let data = FileManager.default.contents(atPath: path),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
    else { return "" }
    return "\(plist)".lowercased()
  }

  static func children(_ folder: String) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
      .filter { $0 != ".DS_Store" }
      .map { folder + "/" + $0 }
  }

  /// Allocated bytes of a file or folder.
  static func size(_ path: String) -> Int64 {
    let url = URL(fileURLWithPath: path)
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
    guard let top = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
    if top.isSymbolicLink == true { return 0 }
    if top.isDirectory != true { return Int64(top.totalFileAllocatedSize ?? 0) }
    var total: Int64 = 0
    let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
    while let file = walker?.nextObject() as? URL {
      total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
    }
    return total
  }

  static func unavailableSimulators() -> [String] {
    guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun"),
      Shell.run("/usr/bin/xcode-select", ["-p"]).ok
    else { return [] }
    let result = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"])
    guard result.ok, let data = result.output.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let runtimes = json["devices"] as? [String: [[String: Any]]]
    else { return [] }
    return runtimes.values.flatMap { $0 }.compactMap { $0["dataPath"] as? String }
      .map { ($0 as NSString).deletingLastPathComponent }
  }

  /// Dates of Time Machine's own local snapshots. macOS update snapshots are not included.
  static func localSnapshotDates() -> [String] {
    let out = Shell.run("/usr/bin/tmutil", ["listlocalsnapshotdates", "/"]).output
    return out.split(separator: "\n").map(String.init).filter { $0.first?.isNumber == true }
  }

  /// Removes the items: files to the Trash, simulators and snapshots by their
  /// own tools. Things only an administrator can move share one prompt.
  struct CleanResult {
    var problems: [String] = []
    /// Items macOS protects, which nobody can move without turning protections off.
    var protected = 0
  }

  static func clean(_ items: [StorageItem]) -> CleanResult {
    var result = CleanResult()
    var adminCommands: [String] = []
    let trash = home + "/.Trash"
    for item in items {
      switch item.kind {
      case .files:
        for path in item.paths {
          do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
          } catch {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            // Only things another user owns need an administrator. Something
            // the user owns but can't move is protected by macOS, and an
            // administrator can't move it either.
            let owner = (try? FileManager.default.attributesOfItem(atPath: path)[.ownerAccountID] as? NSNumber)?.uint32Value
            guard let owner, owner != getuid() else {
              result.protected += 1
              continue
            }
            let name = (path as NSString).lastPathComponent
            let target = trash + "/" + uniqueName(name, in: trash)
            adminCommands.append("/bin/mv -f \(Shell.quote(path)) \(Shell.quote(target))")
          }
        }
      case .simulators:
        let run = Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
        if !run.ok { result.problems.append("Simulators: \(run.output.trimmed)") }
      case .snapshots:
        for date in item.paths { adminCommands.append("/usr/bin/tmutil deletelocalsnapshots \(Shell.quote(date))") }
      }
    }
    if !adminCommands.isEmpty {
      let run = Shell.admin(adminCommands, prompt: "RemoveMacAI needs your password to move items only an administrator can change.")
      if !run.ok { result.problems.append(Shell.adminError(run)) }
    }
    return result
  }

  static func uniqueName(_ name: String, in folder: String) -> String {
    var candidate = name
    var n = 2
    while FileManager.default.fileExists(atPath: folder + "/" + candidate) {
      let ext = (name as NSString).pathExtension
      let base = (name as NSString).deletingPathExtension
      candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
      n += 1
    }
    return candidate
  }
}
