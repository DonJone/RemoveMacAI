import Foundation
import UAF

/// Apple's asset service: how much of each model set is on disk, and removing it.
enum Models {
  static func available() -> Bool {
    UAFLoad() && UAFAssetType(Catalog.foundationModels) != nil
  }

  /// Bytes on disk for a set, or nil when the service does not say. The
  /// inventory comes first: the per-set status can report 0 for installed sets.
  static func bytes(_ set: String) -> Int64? {
    if let model = Catalog.modelSet(set), let inventory = inventory() {
      return inventory[model.assetType] ?? 0
    }
    var error: NSError?
    let n = UAFDownloadedBytes(set, &error)
    return n >= 0 ? n : nil
  }

  /// Bytes of present assets by asset type, from the asset service's inventory.
  static func parseInventory(_ info: [String: Any]) -> [String: Int64] {
    var bytes: [String: Int64] = [:]
    for asset in info["SystemAssets"] as? [[String: Any]] ?? [] {
      guard asset["isPresentOnDevice"] as? Bool == true,
        let meta = asset["metadata"] as? [String: Any],
        let type = meta["AssetType"] as? String
      else { continue }
      let size = meta["com.apple.UnifiedAssetFramework.UnarchivedSize"] ?? meta["_UnarchivedSize"]
      bytes[type, default: 0] += Int64("\(size ?? 0)") ?? 0
    }
    return bytes
  }

  private static var cached: (at: Date, value: [String: Int64]?)?

  static func inventory() -> [String: Int64]? {
    if let c = cached, Date().timeIntervalSince(c.at) < 1 { return c.value }
    var error: NSError?
    let value = UAFLoad() ? UAFInformation(&error).map { parseInventory($0 as? [String: Any] ?? [:]) } : nil
    cached = (Date(), value)
    return value
  }

  /// Whether anything of the set may still be on disk: tracked bytes, or files
  /// in its asset folder. A folder macOS will not let us read counts as present.
  static func present(_ set: String) -> Bool {
    if (bytes(set) ?? 0) > 0 { return true }
    guard let model = Catalog.modelSet(set) else { return false }
    let path = "/System/Library/AssetsV2/" + model.assetType.replacingOccurrences(of: ".", with: "_")
    guard FileManager.default.fileExists(atPath: path) else { return false }
    guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return true }
    return !items.isEmpty
  }

  /// A total is only known when every selected set answered.
  static func total(_ sets: [String], read: (String) -> Int64? = bytes) -> Int64? {
    var total: Int64 = 0
    for set in sets {
      guard let bytes = read(set) else { return nil }
      total += bytes
    }
    return total
  }

  /// Splits the sets into those whose asset type still matches the catalog and
  /// those to leave alone, with the reason. Refuses anything outside the catalog.
  static func matching(_ sets: [String], assetType: (String) -> String? = UAFAssetType) throws
    -> (matched: [String], skipped: [(String, String)])
  {
    var matched: [String] = []
    var skipped: [(String, String)] = []
    for name in sets {
      guard let known = Catalog.modelSet(name) else { throw Failure("unknown model set \(name)") }
      let type = assetType(name)
      if type == known.assetType {
        matched.append(name)
      } else if let type {
        skipped.append((name, "its asset type is \(type) on this version of macOS, so it was left alone"))
      } else {
        skipped.append((name, "not found on this version of macOS, so it was left alone"))
      }
    }
    return (matched, skipped)
  }

  /// Removes the downloaded models of these sets, one set per request, so one
  /// the service rejects does not stop the rest. Refuses anything outside the
  /// catalog, and leaves alone any set whose asset type no longer matches it.
  /// Returns the sets that stayed, with the reason.
  @discardableResult
  static func remove(_ sets: [String], timeout: TimeInterval = 120) throws -> [(String, String)] {
    guard !sets.isEmpty else { throw Failure("no model sets selected") }
    var (matched, failed) = try matching(sets)
    for name in matched where present(name) {
      let done = DispatchSemaphore(value: 0)
      var failure: NSError?
      UAFResetAssetSets([name]) { error in
        failure = error as NSError?
        done.signal()
      }
      if done.wait(timeout: .now() + timeout) != .success {
        failed.append((name, "no answer in \(Int(timeout)) seconds"))
      } else if let failure {
        let detail = failure.userInfo.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        failed.append((name, "\(failure.domain) \(failure.code) \(detail)"))
      }
    }
    return failed
  }
}

/// Whether a feature is off, and whether our profile locks it off.
enum FeatureState: Equatable {
  case lockedOff, off, on, unknown

  var isOff: Bool { self == .lockedOff || self == .off }
}

/// The final verification snapshot, kept separate from reset acknowledgements.
struct ModelRemovalResult {
  let before: Int64?
  let after: Int64?
  let failures: [(String, String)]
  let verified: Bool

  var complete: Bool { failures.isEmpty && verified && after == 0 }

  var deletedBytes: Int64? {
    guard let before, let after else { return nil }
    return max(0, before - after)
  }
}

enum Settings {
  static func state(_ feature: Feature) -> FeatureState {
    let forced =
      feature.restrictions.allSatisfy { isForced("com.apple.applicationaccess", $0, value: false) }
      && feature.preferences.allSatisfy { isForced($0.domain, $0.key, value: $0.off) }
    let locked = forced && (!feature.restrictions.isEmpty || !feature.preferences.isEmpty)
    if locked || lockedByProfile(feature) { return .lockedOff }
    if !feature.preferences.isEmpty,
      feature.preferences.allSatisfy({ value($0.domain, $0.key) == $0.off })
    {
      return .off
    }
    // A feature that is only models is on while its models are on disk.
    if feature.restrictions.isEmpty && feature.preferences.isEmpty {
      return modelState(feature.modelSets)
    }
    return .on
  }

  static func modelState(_ sets: [String], read: (String) -> Int64? = Models.bytes) -> FeatureState {
    let readings = sets.map(read)
    if readings.contains(where: { ($0 ?? 0) > 0 }) { return .on }
    return readings.allSatisfy { $0 == 0 } ? .off : .unknown
  }

  /// Features with no switch of their own (only models) count as locked off
  /// while our profile keeps their models from downloading.
  static func lockedByProfile(_ feature: Feature) -> Bool {
    guard feature.restrictions.isEmpty, feature.preferences.isEmpty else { return false }
    let profile = Profile.installed()
    return profile.on && profile.ai && !profile.kept.contains(feature.id)
  }

  static func isForced(_ domain: String, _ key: String, value: Bool) -> Bool {
    CFPreferencesAppSynchronize(domain as CFString)
    return CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
      && self.value(domain, key) == value
  }

  static func value(_ domain: String, _ key: String) -> Bool? {
    CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
  }
}

struct Failure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
