import Foundation

/// A sidebar section of the catalog.
enum TweakGroup: String, CaseIterable, Identifiable {
  case privacy, annoyances, apps, finder, windows, typing

  var id: String { rawValue }

  var title: String {
    switch self {
    case .privacy: return L10n.s("Privacy", "隐私保护")
    case .annoyances: return L10n.s("Annoyances", "系统干扰与弹窗")
    case .apps: return L10n.s("Apple Apps", "系统内置应用")
    case .finder: return L10n.s("Finder", "访达设置")
    case .windows: return L10n.s("Dock and Windows", "程序坞与窗口")
    case .typing: return L10n.s("Typing", "键盘与键入")
    }
  }

  var symbol: String {
    switch self {
    case .privacy: return "hand.raised"
    case .annoyances: return "bell.slash"
    case .apps: return "square.grid.2x2"
    case .finder: return "folder"
    case .windows: return "dock.rectangle"
    case .typing: return "keyboard"
    }
  }

  var summary: String {
    switch self {
    case .privacy: return L10n.s("Stop your Mac sending analytics, searches and recordings to Apple.", "禁止 Mac 向 Apple 发送分析数据、搜索记录和录音。")
    case .annoyances: return L10n.s("Turn off the pop-ups, widgets and surprises nobody asked for.", "关闭未经允许的烦人弹窗、桌面小组件与意外动作。")
    case .apps: return L10n.s("Quiet the Apple apps you don't use. macOS won't let anyone delete them.", "精简不常用的系统预装应用，减少无用推荐与干扰。")
    case .finder: return L10n.s("Show what Finder hides and stop the clutter it leaves behind.", "显示访达隐藏的实用信息，阻止生成冗余缓存文件。")
    case .windows: return L10n.s("A faster Dock without the extra icons and animations.", "打造更高效、纯净、无冗余动画的程序坞。")
    case .typing: return L10n.s("Stop macOS rewriting what you type.", "关闭 macOS 的输入法自动更正与多余符号替换。")
    }
  }
}

/// A named starting selection.
enum Preset: String, CaseIterable, Identifiable {
  case recommended, privacy

  var id: String { rawValue }

  var title: String {
    switch self {
    case .recommended: return L10n.s("Recommended", "推荐配置")
    case .privacy: return L10n.s("Maximum privacy", "极致隐私")
    }
  }

  var summary: String {
    switch self {
    case .recommended: return L10n.s("Apple Intelligence off, no analytics or ads, fewer pop-ups. Nothing you rely on stops working.", "彻底关闭 Apple Intelligence，禁用分析与广告，减少弹窗，不影响常用基础功能。")
    case .privacy: return L10n.s("Everything in Recommended, plus Game Center and Safari's search suggestions off.", "包含“推荐配置”的全部内容，并额外关闭 Game Center 与 Safari 搜索联想建议。")
    }
  }
}

/// One setting a tweak changes.
enum Change: Equatable {
  /// A restriction key the profile sets to false.
  case restriction(String)
  /// A preference the profile forces, so it can't be changed back by hand.
  case forced(String, String, PlistValue)
  /// A preference written for the current user.
  case pref(String, String, PlistValue, currentHost: Bool = false)
  /// A launchd agent in the user's session, disabled and unloaded.
  case service(String)
  /// Dock icons removed by bundle identifier.
  case dockRemove([String])
  /// ~/Library shown in Finder.
  case showLibrary

  var inProfile: Bool {
    switch self {
    case .restriction, .forced: return true
    default: return false
    }
  }

  /// The journal key; two tweaks never change the same thing.
  var key: String {
    switch self {
    case .restriction(let k): return "restriction:\(k)"
    case .forced(let d, let k, _): return "forced:\(d):\(k)"
    case .pref(let d, let k, _, let host): return "pref:\(d):\(k)" + (host ? ":currentHost" : "")
    case .service(let l): return "service:\(l)"
    case .dockRemove(let ids): return "dock:" + ids.joined(separator: ",")
    case .showLibrary: return "library"
    }
  }

  /// The equivalent command, shown before anything changes.
  var command: String {
    switch self {
    case .restriction(let k): return "profile: com.apple.applicationaccess \(k) = false"
    case .forced(let d, let k, let v): return "profile: \(d) \(k) = \(v) (locked)"
    case .pref(let d, let k, let v, let host):
      let type: String
      switch v {
      case .bool: type = "-bool"
      case .int: type = "-int"
      case .double: type = "-float"
      case .string: type = "-string"
      }
      let value: String
      if case .string(let s) = v { value = "\"\(s)\"" } else { value = v.description }
      return "defaults\(host ? " -currentHost" : "") write \(d) \"\(k)\" \(type) \(value)"
    case .service(let l): return "launchctl disable gui/$UID/\(l) && launchctl bootout gui/$UID/\(l)"
    case .dockRemove(let ids): return "remove from the Dock: " + ids.joined(separator: ", ")
    case .showLibrary: return "chflags nohidden ~/Library"
    }
  }
}

struct Tweak: Identifiable {
  let id: String
  let group: TweakGroup
  let title: String
  let detail: String
  var caveat: String? = nil
  let changes: [Change]
  /// Processes that read the setting only at launch.
  var restart: [String] = []
  var presets: Set<Preset> = []
  /// The first macOS version (major, minor) that has the setting.
  var since: (Int, Int) = (14, 0)

  var inProfile: Bool { changes.contains { $0.inProfile } }

  var supported: Bool {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return (os.majorVersion, os.minorVersion) >= since
  }
}

enum Tweaks {
  static var all: [Tweak] {
    [
      // MARK: Privacy
      Tweak(
        id: "analytics", group: .privacy,
        title: L10n.s("Turn off Mac Analytics", "关闭 Mac 分析数据共享"),
        detail: L10n.s("Stops your Mac sending diagnostic and usage data to Apple and to app developers.", "禁止 Mac 向 Apple 及第三方应用开发者发送诊断与使用数据。"),
        changes: [.restriction("allowDiagnosticSubmission")], presets: [.recommended, .privacy]),
      Tweak(
        id: "personalized-ads", group: .privacy,
        title: L10n.s("Turn off personalized ads", "关闭个性化广告"),
        detail: L10n.s("Stops Apple using what you do in its apps to target ads in the App Store, News and Stocks.", "禁止 Apple 根据你的应用使用习惯在 App Store、股市等展示定向广告。"),
        changes: [.restriction("allowApplePersonalizedAdvertising")], presets: [.recommended, .privacy]),
      Tweak(
        id: "improve-siri", group: .privacy,
        title: L10n.s("Turn off Improve Siri and Dictation", "关闭“改进 Siri 与听写”"),
        detail: L10n.s("Stops Apple storing and reviewing recordings of your Siri and dictation requests.", "禁止 Apple 存储并人工复核你的 Siri 与语音听写录音。"),
        changes: [.forced("com.apple.assistant.support", "Siri Data Sharing Opt-In Status", .int(2))],
        presets: [.recommended, .privacy]),
      Tweak(
        id: "improve-search", group: .privacy,
        title: L10n.s("Turn off Improve Search", "关闭“改进搜索”"),
        detail: L10n.s("Stops Apple keeping your Spotlight, Safari and Look Up searches to improve search.", "禁止 Apple 收集并留存你在聚焦搜索、Safari 与“查询”中的搜索词。"),
        changes: [.forced("com.apple.assistant.support", "Search Queries Data Sharing Status", .int(2))],
        presets: [.recommended, .privacy]),
      Tweak(
        id: "spotlight-web", group: .privacy,
        title: L10n.s("Turn off Spotlight internet results", "关闭聚焦网络搜索结果"),
        detail: L10n.s("Keeps Spotlight searches on your Mac instead of sending them to Apple for web suggestions.", "聚焦搜索仅保留本地结果，不再将搜索内容发送给 Apple 获取网页建议。"),
        changes: [.restriction("allowSpotlightInternetResults")], presets: [.recommended, .privacy]),
      Tweak(
        id: "lookup-suggestions", group: .privacy,
        title: L10n.s("Turn off Look Up suggestions", "关闭“查询”联机建议"),
        detail: L10n.s("Stops Look Up sending the words you select to Apple for web results.", "选词执行“查询”时不再将选定文本发送至 Apple 获取网络联机内容。"),
        changes: [.forced("com.apple.lookup.shared", "LookupSuggestionsDisabled", .bool(true))],
        presets: [.recommended, .privacy]),
      Tweak(
        id: "safari-suggestions", group: .privacy,
        title: L10n.s("Turn off Safari search suggestions", "关闭 Safari 搜索建议"),
        detail: L10n.s("Stops Safari sending what you type in the address bar to your search engine and to Apple.", "在地址栏输入内容时，不再实时向搜索引擎与 Apple 发送键入内容以获取联想。"),
        caveat: L10n.s("The address bar no longer suggests searches as you type.", "地址栏将不再随打字即时提供联想搜索建议。"),
        changes: [
          .forced("com.apple.Safari", "UniversalSearchEnabled", .bool(false)),
          .forced("com.apple.Safari", "SuppressSearchSuggestions", .bool(true)),
        ], presets: [.privacy]),
      Tweak(
        id: "game-center", group: .privacy,
        title: L10n.s("Turn off Game Center", "关闭 Game Center"),
        detail: L10n.s("Turns Game Center off, with its sign-in prompts, friend requests and notifications.", "关闭 Game Center 服务及其登录弹窗、好友请求和相关通知。"),
        caveat: L10n.s("Games that need Game Center to save progress or play online lose that.", "依赖 Game Center 云存档或联机的游戏可能会受到影响。"),
        changes: [.restriction("allowGameCenter")], presets: [.privacy]),

      // MARK: Annoyances
      Tweak(
        id: "click-to-desktop", group: .annoyances,
        title: L10n.s("Stop clicks on the wallpaper hiding windows", "禁止点击墙纸显示桌面"),
        detail: L10n.s("Stops every window sliding away when you click the wallpaper by mistake.", "防止误触墙纸空白区域导致所有窗口散开退避到屏幕边缘。"),
        changes: [.pref("com.apple.WindowManager", "EnableStandardClickToShowDesktop", .bool(false))],
        presets: [.recommended]),
      Tweak(
        id: "desktop-widgets", group: .annoyances,
        title: L10n.s("Hide desktop widgets", "隐藏桌面小组件"),
        detail: L10n.s("Hides widgets on the desktop, including in Stage Manager.", "在桌面及台前调度模式下隐藏所有小组件。"),
        changes: [
          .pref("com.apple.WindowManager", "StandardHideWidgets", .bool(true)),
          .pref("com.apple.WindowManager", "StageManagerHideWidgets", .bool(true)),
        ]),
      Tweak(
        id: "media-keys", group: .annoyances,
        title: L10n.s("Stop the play key opening Music", "禁止播放键默认启动“音乐”App"),
        detail: L10n.s("Stops the play key opening Music when nothing else is playing.", "当无任何媒体播放时，按键盘播放键不会自动打开系统“音乐”App。"),
        caveat: L10n.s("The play key no longer starts Music itself.", "播放键将无法用于直接唤醒“音乐”App。"),
        changes: [.service("com.apple.rcd")], presets: [.recommended]),
      Tweak(
        id: "iphone-mirroring", group: .annoyances,
        title: L10n.s("Turn off iPhone Mirroring", "关闭 iPhone 镜像"),
        detail: L10n.s("Turns iPhone Mirroring off, so the app and its prompts go away.", "关闭 iPhone 镜像功能并隐藏其系统提示。"),
        changes: [.restriction("allowiPhoneMirroring")], since: (15, 0)),

      // MARK: Apple apps
      Tweak(
        id: "music-classic", group: .apps,
        title: L10n.s("Turn off Apple Music in the Music app", "音乐 App 关闭 Apple Music 订阅推荐"),
        detail: L10n.s("Turns the Music app back into a plain player for your own library, without the store and subscription prompts.", "将“音乐”还原为纯粹的本地音乐播放器，隐藏在线商店与 Apple Music 订阅推荐。"),
        caveat: L10n.s("Apple Music subscribers lose streaming.", "Apple Music 订阅用户将无法直接在线串流。"),
        changes: [.restriction("allowMusicService")]),
      Tweak(
        id: "book-store", group: .apps,
        title: L10n.s("Turn off the Book Store", "图书 App 关闭“书店”"),
        detail: L10n.s("Removes the store from the Books app and keeps your own books.", "从“图书”App 中移除在线书店，仅保留本地书库。"),
        changes: [.restriction("allowBookstore")], since: (15, 0)),
      Tweak(
        id: "dock-apple-apps", group: .apps,
        title: L10n.s("Remove unused Apple apps from the Dock", "从程序坞移除不常用的系统预装应用"),
        detail: L10n.s("Removes News, TV, Music, Podcasts, Books, Freeform, Maps and Stocks from the Dock. The apps stay installed.", "从程序坞移除播客、图书、无边记、地图、股市等图标（应用本身仍保留在系统中）。"),
        changes: [.dockRemove([
          "com.apple.news", "com.apple.TV", "com.apple.Music", "com.apple.podcasts", "com.apple.iBooksX",
          "com.apple.freeform", "com.apple.Maps", "com.apple.stocks",
        ])], restart: ["Dock"]),

      // MARK: Finder
      Tweak(
        id: "file-extensions", group: .finder,
        title: L10n.s("Show file extensions", "始终显示文件扩展名"),
        detail: L10n.s("Shows the full name of every file, so a file pretending to be a document is easier to spot.", "在访达中显示所有文件的扩展名，更易识别伪装类型。"),
        changes: [.pref(Prefs.global, "AppleShowAllExtensions", .bool(true))], restart: ["Finder"],
        presets: [.recommended, .privacy]),
      Tweak(
        id: "hidden-files", group: .finder,
        title: L10n.s("Show hidden files", "显示隐藏文件"),
        detail: L10n.s("Shows the files macOS hides, such as .gitignore and .zshrc. Press Command-Shift-Period to toggle it too.", "在访达中始终显示以点开头的隐藏文件。快捷键 Command-Shift-. 也可随时切换。"),
        changes: [.pref("com.apple.finder", "AppleShowAllFiles", .bool(true))], restart: ["Finder"]),
      Tweak(
        id: "path-bar", group: .finder,
        title: L10n.s("Show the path bar", "显示路径栏"),
        detail: L10n.s("Shows where the current folder is at the bottom of every Finder window.", "在每个访达窗口底部显示当前文件夹的层级路径。"),
        changes: [.pref("com.apple.finder", "ShowPathbar", .bool(true))], restart: ["Finder"],
        presets: [.recommended]),
      Tweak(
        id: "status-bar", group: .finder,
        title: L10n.s("Show the status bar", "显示状态栏"),
        detail: L10n.s("Shows the number of items and the free space at the bottom of Finder windows.", "在访达窗口底部显示项目数量和可用磁盘空间。"),
        changes: [.pref("com.apple.finder", "ShowStatusBar", .bool(true))], restart: ["Finder"]),
      Tweak(
        id: "folders-first", group: .finder,
        title: L10n.s("Keep folders above files", "按名称排序时文件夹置顶"),
        detail: L10n.s("Keeps folders above files when sorting by name.", "在访达中按名称排序时，始终优先将文件夹排在文件前面。"),
        changes: [.pref("com.apple.finder", "_FXSortFoldersFirst", .bool(true))], restart: ["Finder"],
        presets: [.recommended]),
      Tweak(
        id: "search-this-folder", group: .finder,
        title: L10n.s("Search the current folder", "默认搜索当前文件夹"),
        detail: L10n.s("Makes Finder search the folder you're in, not the whole Mac.", "在访达执行搜索时，默认仅搜索当前目录而非整台 Mac。"),
        changes: [.pref("com.apple.finder", "FXDefaultSearchScope", .string("SCcf"))], restart: ["Finder"]),
      Tweak(
        id: "extension-warning", group: .finder,
        title: L10n.s("Skip the extension change warning", "跳过更改扩展名时的警告提示"),
        detail: L10n.s("Stops Finder asking for confirmation each time you change a file's extension.", "修改文件扩展名时直接生效，不再弹出繁琐的确认对话框。"),
        changes: [.pref("com.apple.finder", "FXEnableExtensionChangeWarning", .bool(false))], restart: ["Finder"]),
      Tweak(
        id: "path-in-title", group: .finder,
        title: L10n.s("Show the full path in the title bar", "窗口标题栏显示完整路径"),
        detail: L10n.s("Shows the full folder path at the top of Finder windows.", "在访达窗口标题栏中直接显示当前文件夹的完整路径。"),
        changes: [.pref("com.apple.finder", "_FXShowPosixPathInTitle", .bool(true))], restart: ["Finder"]),
      Tweak(
        id: "network-ds-store", group: .finder,
        title: L10n.s("Stop .DS_Store files on network drives", "禁止在网络共享宗卷上创建 .DS_Store"),
        detail: L10n.s("Stops Finder leaving .DS_Store files in shared folders on other computers.", "防止访达在网络驱动器或共享文件夹中残留 .DS_Store 隐藏文件。"),
        changes: [.pref("com.apple.desktopservices", "DSDontWriteNetworkStores", .bool(true))],
        presets: [.recommended]),
      Tweak(
        id: "trash-30-days", group: .finder,
        title: L10n.s("Empty the Trash after 30 days", "30 天后自动清倒废纸篓"),
        detail: L10n.s("Deletes items that have been in the Trash for 30 days, so it stops filling the disk.", "自动彻底清理放入废纸篓超过 30 天的项目，释放存储。"),
        changes: [.pref("com.apple.finder", "FXRemoveOldTrashItems", .bool(true))], restart: ["Finder"]),
      Tweak(
        id: "save-locally", group: .finder,
        title: L10n.s("Save new documents on this Mac", "默认将新文稿存储在本地"),
        detail: L10n.s("Makes Save dialogs start on your Mac instead of iCloud Drive.", "保存新文件时默认定位到 Mac 本地目录而非 iCloud 云盘。"),
        changes: [.pref(Prefs.global, "NSDocumentSaveNewDocumentsToCloud", .bool(false))]),
      Tweak(
        id: "expanded-save", group: .finder,
        title: L10n.s("Expand Save dialogs", "默认展开存储面板"),
        detail: L10n.s("Opens Save dialogs with the full folder browser instead of the small version.", "存储文件时默认打开完整文件夹浏览面板，而非折叠的精简视图。"),
        changes: [.pref(Prefs.global, "NSNavPanelExpandedStateForSaveMode", .bool(true))]),
      Tweak(
        id: "show-library", group: .finder,
        title: L10n.s("Show the Library folder", "显示个人资源库文件夹 (~/Library)"),
        detail: L10n.s("Shows the hidden Library folder in your home folder.", "在访达个人主目录中解除资源库 (Library) 文件夹的隐藏属性。"),
        changes: [.showLibrary]),

      // MARK: Dock and windows
      Tweak(
        id: "dock-recents", group: .windows,
        title: L10n.s("Hide recent apps in the Dock", "程序坞隐藏最近使用应用"),
        detail: L10n.s("Stops the Dock adding apps you opened recently.", "禁止在程序坞右侧单独区域显示最近打开过的应用程序。"),
        changes: [.pref("com.apple.dock", "show-recents", .bool(false))], restart: ["Dock"],
        presets: [.recommended]),
      Tweak(
        id: "dock-delay", group: .windows,
        title: L10n.s("Remove the Dock auto-hide delay", "消除程序坞自动隐藏的响应延迟"),
        detail: L10n.s("Shows a hidden Dock straight away instead of after half a second.", "鼠标滑至屏幕边缘时即刻弹出程序坞，消除半秒等待时间。"),
        changes: [.pref("com.apple.dock", "autohide-delay", .double(0))], restart: ["Dock"]),
      Tweak(
        id: "dock-bounce", group: .windows,
        title: L10n.s("Stop Dock icons bouncing", "禁用程序坞图标启动弹跳动画"),
        detail: L10n.s("Stops Dock icons bouncing while apps open.", "启动应用程序时图标保持静止，不再在程序坞上持续弹跳。"),
        changes: [.pref("com.apple.dock", "launchanim", .bool(false))], restart: ["Dock"]),
      Tweak(
        id: "minimize-to-app", group: .windows,
        title: L10n.s("Minimize windows into their app icon", "窗口最小化至应用图标"),
        detail: L10n.s("Keeps minimized windows inside their app's icon instead of filling the Dock.", "将最小化的窗口折叠至对应的应用图标中，不再占用程序坞右侧栏位。"),
        changes: [.pref("com.apple.dock", "minimize-to-application", .bool(true))], restart: ["Dock"]),
      Tweak(
        id: "window-animations", group: .windows,
        title: L10n.s("Turn off window opening animations", "关闭窗口打开缩放动画"),
        detail: L10n.s("Opens new windows instantly instead of zooming them in.", "打开新窗口时立即瞬间显示，跳过缩放过渡动效。"),
        changes: [.pref(Prefs.global, "NSAutomaticWindowAnimationsEnabled", .bool(false))]),
      Tweak(
        id: "tile-margins", group: .windows,
        title: L10n.s("Remove gaps between tiled windows", "消除平铺并排窗口间的缝隙边距"),
        detail: L10n.s("Removes the margins around windows you tile to the sides of the screen.", "将窗口分屏并排平铺到屏幕两侧时，移除中间及四周的留白外边距。"),
        changes: [.pref("com.apple.WindowManager", "EnableTiledWindowMargins", .bool(false))], since: (15, 0)),
      Tweak(
        id: "screenshot-shadow", group: .windows,
        title: L10n.s("Remove shadows from window screenshots", "截取窗口截图时移除外圈阴影"),
        detail: L10n.s("Takes window screenshots without the large drop shadow around them.", "使用快捷键截取窗口图像时，仅保存窗口本身并剔除黑色投影阴影。"),
        changes: [.pref("com.apple.screencapture", "disable-shadow", .bool(true))], restart: ["SystemUIServer"]),

      // MARK: Typing
      Tweak(
        id: "autocorrect", group: .typing,
        title: L10n.s("Turn off autocorrect", "关闭拼写自动更正"),
        detail: L10n.s("Stops macOS correcting words as you type.", "打字时禁止系统自动纠正单词拼写。"),
        changes: [.pref(Prefs.global, "NSAutomaticSpellingCorrectionEnabled", .bool(false))]),
      Tweak(
        id: "smart-punctuation", group: .typing,
        title: L10n.s("Turn off smart quotes and dashes", "关闭智能引号与破折号替换"),
        detail: L10n.s("Keeps straight quotes and double hyphens as you typed them, which code and terminals need.", "保留原始直引号和双连字符，防止编写代码或终端命令时被替换为弯引号。"),
        changes: [
          .pref(Prefs.global, "NSAutomaticQuoteSubstitutionEnabled", .bool(false)),
          .pref(Prefs.global, "NSAutomaticDashSubstitutionEnabled", .bool(false)),
        ]),
      Tweak(
        id: "double-space-period", group: .typing,
        title: L10n.s("Turn off period on double space", "关闭双击空格输入句号"),
        detail: L10n.s("Stops two spaces turning into a period.", "连按两次空格键时不再自动替换为句号加空格。"),
        changes: [.pref(Prefs.global, "NSAutomaticPeriodSubstitutionEnabled", .bool(false))]),
      Tweak(
        id: "auto-capitalize", group: .typing,
        title: L10n.s("Turn off automatic capitals", "关闭句首字母自动大写"),
        detail: L10n.s("Stops macOS capitalizing the first word of each sentence.", "打字输入时不再自动将每句话的首字母转换为大写。"),
        changes: [.pref(Prefs.global, "NSAutomaticCapitalizationEnabled", .bool(false))]),
      Tweak(
        id: "key-repeat", group: .typing,
        title: L10n.s("Repeat held keys instead of showing accents", "长按按键连续连打而非弹出重音菜单"),
        detail: L10n.s("Repeats a key while you hold it, instead of opening the accent menu.", "按住键盘按键时持续重复输出该字符，而非弹出重音字母挑选菜单。"),
        caveat: L10n.s("Type accents with Option shortcuts or the Character Viewer instead.", "如需输入重音字符，可使用 Option 组合键或字符检视器。"),
        changes: [.pref(Prefs.global, "ApplePressAndHoldEnabled", .bool(false))]),
    ]
  }

  static func tweak(_ id: String) -> Tweak? { all.first { $0.id == id } }

  /// Maximum privacy builds on Recommended.
  static func preset(_ preset: Preset) -> [Tweak] {
    let names: Set<Preset> = preset == .privacy ? [.recommended, .privacy] : [preset]
    return all.filter { !$0.presets.isDisjoint(with: names) && $0.supported }
  }
}
