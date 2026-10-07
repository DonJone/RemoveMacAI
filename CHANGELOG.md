# Changelog

## 1.0.1

- 针对 macOS 简体中文环境进行全局双语本地化适配（CLI 命令行与 GUI 界面）。
- 新增环境变量 `REMOVEMACAI_LANG` 支持快速切换/锁定中英文展示。
- 修复 macOS 27 环境下 Swift 宏相关构建兼容性。
- 完善模型占用标签与单元自检测试兼容性。

## 1.0.0

RemoveMacAI is now a debloater for macOS, with a native app. Apple Intelligence works as before and is one part of it.

- The app: an overview of the Mac, every setting with what it does, a review of each change before it happens, and Undo Everything. It opens from Applications, or with `removemacai app`. The app and the command line are the same program and share one undo history.
- 40 tweaks in six sections: Privacy (Mac Analytics, personalized ads, Improve Siri and Dictation, Improve Search, Spotlight internet results, Look Up and Safari suggestions, Game Center), Annoyances, Apple Apps, Finder, Dock and Windows, and Typing.
- Two presets: Recommended and Maximum privacy.
- Background items: other apps' launch agents and daemons, each switched off and back on.
- Storage: old macOS installers, aerial wallpaper videos, iPhone and iPad update files, Xcode leftovers, unavailable simulators, app caches, Time Machine local snapshots and Apple's optional apps, moved to the Trash.
- Locked settings share the Apple Intelligence profile, which records what it holds. Other settings are written with their previous value saved, and undo restores exactly that value.
- New commands: `tweaks`, `apply`, `undo`, `background`, `clean`, `export` and `app`. `on` turns Apple Intelligence back on and keeps the other changes; `revert` undoes everything.
- `export` writes the profile for an MDM.
- `install.sh app` installs the app in Applications.

## 0.2.5

- `off` no longer counts a model set the asset service can't size as 0. Those sizes show as unknown, and when removal fails or can't be confirmed, `off` says the run is incomplete, leaves the profile in place and exits with status 1. Contributed by Daniel Traynor in #1.
- `off --keep` says when a kept feature is switched off. `--keep` stops the profile from locking a feature, but it doesn't turn the feature back on. Reported by J-Liu in #8.

## 0.2.4

- `off` no longer gives up on every model when one set doesn't match what RemoveMacAI expects. On macOS 26.5 the Spatial Photos set failed the check, so nothing was removed. That set is now left alone and named, and the rest are removed. Reported by halilmertogut in #4.
- `--dry-run` names any set it would leave alone.

## 0.2.3

- Model sizes now come from the asset service's inventory. On some Macs, including macOS 27.0.1, the per-set status reported 0 for installed models, so `off` removed nothing. Diagnosed by Vlad Tulitu in #2.
- When `off` removes models, it also asks the asset service to remove sets whose asset folders still hold files.
- Releases are built from their tag by GitHub Actions and carry a build provenance attestation.

## 0.2.2

- Homebrew installs the prebuilt binary, so it no longer needs Xcode or the Command Line Tools.
- The release download includes `LICENSE` and `THIRD-PARTY-NOTICES.md`, with the MIT license of [pared](https://github.com/4evy/pared).

## 0.2.1

- RemoveMacAI no longer says the space is free straight after deleting the models. macOS deletes the files on its own schedule, and `off`, `status` and the README now say so.
- It says so when Apple's asset service doesn't answer, instead of reporting the models as gone.

## 0.2.0

- First public release.
