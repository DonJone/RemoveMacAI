# Changelog

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
