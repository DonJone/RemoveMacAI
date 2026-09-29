import Foundation
import UAF

/// Apple's asset service: how much of each model set is on disk, and removing it.
enum Models {
  static func available() -> Bool {
    UAFLoad() && UAFAssetType(Catalog.foundationModels) != nil
  }

  /// Bytes on disk for a set, or nil when the service does not say.
  static func bytes(_ set: String) -> Int64? {
    var error: NSError?
    let n = UAFDownloadedBytes(set, &error)
    return n >= 0 ? n : nil
  }

  static func total(_ sets: [String]) -> Int64 { sets.compactMap(bytes).reduce(0, +) }

  /// Removes the downloaded models of these sets, one set per request, so one
  /// the service rejects does not stop the rest. Refuses anything outside the
  /// catalog, and any set whose asset type no longer matches it. Returns the
  /// sets that failed, with the reason.
  @discardableResult
  static func remove(_ sets: [String], timeout: TimeInterval = 120) throws -> [(String, String)] {
    guard !sets.isEmpty else { throw Failure("no model sets selected") }
    for name in sets {
      guard let known = Catalog.modelSet(name) else { throw Failure("unknown model set \(name)") }
      guard UAFAssetType(name) == known.assetType else {
        throw Failure("\(name) no longer matches this version of RemoveMacAI; nothing removed")
      }
    }
    var failed: [(String, String)] = []
    for name in sets where (bytes(name) ?? 1) > 0 {
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
  case lockedOff, off, on
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
      return feature.modelSets.contains { (Models.bytes($0) ?? 0) > 0 } ? .on : .off
    }
    return .on
  }

  /// Features with no switch of their own (only models) count as locked off
  /// while our profile keeps their models from downloading.
  static func lockedByProfile(_ feature: Feature) -> Bool {
    guard feature.restrictions.isEmpty, feature.preferences.isEmpty else { return false }
    let profile = Profile.installed()
    return profile.on && !profile.kept.contains(feature.id)
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
