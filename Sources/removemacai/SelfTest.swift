import Foundation

/// Checks the parts that must never go wrong, runnable without Xcode:
/// `removemacai selftest`. Touches nothing on the system.
func selfTest() -> Bool {
  var failed = 0
  func check(_ ok: Bool, _ what: String) {
    print((ok ? Term.green("pass ") : Term.red("FAIL ")) + what)
    if !ok { failed += 1 }
  }
  func throwsFailure(_ body: () throws -> Void) -> Bool {
    do { try body() } catch is Failure { return true } catch { return false }
    return false
  }

  check(Set(Catalog.setsToRemove(keeping: [])) == Set(Catalog.modelSets.map(\.name)),
    "off removes every model set")
  let keptWriting = Catalog.setsToRemove(keeping: ["writing-tools"])
  check(!keptWriting.contains(Catalog.foundationModels) && keptWriting.contains(Catalog.spatialModels),
    "a kept feature keeps the models it needs, and only those")
  check(Catalog.setsToRemove(keeping: Set(Catalog.features.map(\.id))).isEmpty,
    "keeping everything removes nothing")
  check(Catalog.features.allSatisfy { $0.modelSets.allSatisfy { Catalog.modelSet($0) != nil } },
    "every model set a feature names is in the catalog")
  check(Set(Catalog.features.map(\.id)).count == Catalog.features.count, "feature names are unique")
  check(throwsFailure { try Models.remove([]) }, "an empty removal is refused before anything is sent")
  check(throwsFailure { try Models.remove(["com.apple.something.else"]) }, "an unknown set is refused")
  let all = Catalog.modelSets.map(\.name)
  let types = Dictionary(uniqueKeysWithValues: Catalog.modelSets.map { ($0.name, $0.assetType) })
  let split = try? Models.matching(all) { $0 == Catalog.spatialModels ? "com.apple.something.else" : types[$0] }
  check(split?.matched == all.filter { $0 != Catalog.spatialModels } && split?.skipped.map { $0.0 } == [Catalog.spatialModels],
    "a set this macOS describes differently is left alone and the rest still go")
  let missing = try? Models.matching(all) { _ in nil }
  check(missing?.matched.isEmpty == true && missing?.skipped.count == all.count,
    "sets this macOS does not have are left alone")
  let parsed = Models.parseInventory(["SystemAssets": [
    ["isPresentOnDevice": true, "metadata": ["AssetType": "a", "_UnarchivedSize": 100]],
    ["isPresentOnDevice": true, "metadata": ["AssetType": "a", "com.apple.UnifiedAssetFramework.UnarchivedSize": "50"]],
    ["isPresentOnDevice": false, "metadata": ["AssetType": "a", "_UnarchivedSize": 999]],
    ["isPresentOnDevice": true, "metadata": ["AssetType": "b"]],
  ]])
  check(parsed == ["a": 150, "b": 0], "the inventory counts only assets that are on disk")

  let sampleSets = ["first", "second"]
  check(Models.total(sampleSets, read: { ["first": Int64(5), "second": 7][$0] }) == 12,
    "known model sizes are added")
  check(Models.total(sampleSets, read: { _ in 0 }) == 0,
    "known zero sizes stay zero")
  check(Models.total(sampleSets, read: { _ in nil }) == nil,
    "failed size queries do not become zero")
  check(Models.total(sampleSets, read: { $0 == "first" ? 0 : nil }) == nil,
    "one unknown size keeps a zero total unknown")
  check(Models.total(sampleSets, read: { $0 == "first" ? 5 : nil }) == nil,
    "one unknown size does not produce a partial total")
  var emptyReads = 0
  check(Models.total([], read: { _ in emptyReads += 1; return nil }) == 0 && emptyReads == 0,
    "an empty total needs no asset queries")

  check(Settings.modelState(sampleSets, read: { _ in nil }) == .unknown,
    "unavailable model sizes produce an unknown feature state")
  check(Settings.modelState(sampleSets, read: { $0 == "first" ? 0 : nil }) == .unknown,
    "zero and unknown sizes do not turn a feature off")
  check(Settings.modelState(sampleSets, read: { $0 == "first" ? nil : 5 }) == .on,
    "a known downloaded model keeps a feature on")
  check(Settings.modelState(sampleSets, read: { _ in 0 }) == .off,
    "a model-only feature is off when every size is zero")
  check(!FeatureState.unknown.isOff && !FeatureState.on.isOff
    && FeatureState.off.isOff && FeatureState.lockedOff.isOff,
    "unknown feature states do not count as off")
  check(Commands.modelSize(nil).contains("unknown") && Commands.modelSize(0).contains("none")
    && Commands.modelSize(1024).contains(Term.size(1024)),
    "model size labels distinguish unknown, empty and downloaded")

  // Every removal dependency below is fake; no asset service is contacted.
  func simulatedRemoval(before: Int64?, after: Int64?, failures: [(String, String)] = [],
    waitExpires: Bool = false) throws -> ModelRemovalResult
  {
    try Commands.removeModels(sampleSets, before: before, remove: { _ in failures },
      total: { _ in after }, wait: { condition in
        let zero = condition()
        return !waitExpires && zero
      })
  }
  do {
    let unknownBefore = try simulatedRemoval(before: nil, after: 0)
    check(unknownBefore.complete && unknownBefore.deletedBytes == nil,
      "removal can be verified without inventing the initial size")
    let unknownAfter = try simulatedRemoval(before: 100, after: nil)
    check(!unknownAfter.complete && unknownAfter.after == nil && unknownAfter.deletedBytes == nil,
      "failed verification does not claim removal or freed space")
    let complete = try simulatedRemoval(before: 100, after: 0)
    check(complete.complete && complete.deletedBytes == 100,
      "verified zero reports the measured removal")

    var verificationReads = 0
    let transient = try Commands.removeModels(sampleSets, before: 100, remove: { _ in [] },
      total: { _ in verificationReads += 1; return verificationReads == 1 ? nil : 0 },
      wait: { condition in
        if condition() { return true }
        return condition()
      })
    check(transient.complete && transient.deletedBytes == 100 && verificationReads == 2,
      "verification waits through an unknown reading and keeps the final snapshot")

    let partial = try simulatedRemoval(before: 100, after: 40,
      failures: [("second", "reset rejected")])
    check(!partial.complete && partial.deletedBytes == 60 && partial.failures.count == 1,
      "partial reset failures preserve measured progress without claiming success")
    for reason in ["reset rejected", "no answer in 120 seconds"] {
      let resetFailure = try simulatedRemoval(before: 100, after: 0, failures: [("second", reason)])
      check(!resetFailure.complete && resetFailure.verified,
        "a reset failure stays incomplete after zero is observed: \(reason)")
    }
    let timedOut = try simulatedRemoval(before: 100, after: 40, waitExpires: true)
    check(!timedOut.complete && !timedOut.verified && timedOut.deletedBytes == 60,
      "verification timeout reports incomplete removal with known progress")
    let unverifiedZero = try simulatedRemoval(before: 100, after: 0, waitExpires: true)
    check(!unverifiedZero.complete && !unverifiedZero.verified,
      "a failed wait cannot become a successful removal")

    for (sets, before) in [([], nil), (sampleSets, Int64(0))] as [([String], Int64?)] {
      var calls = 0
      let skipped = try Commands.removeModels(sets, before: before,
        remove: { _ in calls += 1; return [] }, total: { _ in calls += 1; return nil },
        wait: { _ in calls += 1; return false })
      check(skipped.complete && skipped.after == 0 && calls == 0,
        "empty selections and known zero sizes need no removal or verification")
    }
    var readsAfterThrow = 0
    check(throwsFailure {
      _ = try Commands.removeModels(sampleSets, before: 100,
        remove: { _ in throw Failure("fake reset failure") },
        total: { _ in readsAfterThrow += 1; return 0 },
        wait: { _ in readsAfterThrow += 1; return true })
    } && readsAfterThrow == 0, "throwing resets propagate before verification")
  } catch {
    check(false, "model removal reporting works with fake dependencies: \(error)")
  }

  do {
    let plist = try PropertyListSerialization.propertyList(from: Profile.data(keeping: []), format: nil)
      as! [String: Any]
    let payloads = plist["PayloadContent"] as! [[String: Any]]
    let restrictions = payloads.first { $0["PayloadType"] as? String == "com.apple.applicationaccess" }!
    check(restrictions["allowWritingTools"] as? Bool == false && restrictions["allowAssistant"] as? Bool == false,
      "the profile turns Writing Tools and Siri off")
    let blocks = payloads.first { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".com.apple.MobileAsset") == true }!
    let content = (blocks["PayloadContent"] as! [String: Any])["com.apple.MobileAsset"] as! [String: Any]
    let settings = ((content["Forced"] as! [[String: Any]])[0]["mcx_preference_settings"]) as! [String: String]
    check(settings.count == Catalog.modelSets.count && settings.values.allSatisfy { $0.hasPrefix("https://127.0.0.1:9/") },
      "the profile blocks downloads for every removed set")
    let uuids = payloads.compactMap { $0["PayloadUUID"] as? String } + [plist["PayloadUUID"] as! String]
    check(Set(uuids).count == uuids.count && Profile.uuid("a") == Profile.uuid("a"),
      "payload UUIDs are unique and stable")

    let keep = try PropertyListSerialization.propertyList(from: Profile.data(keeping: ["writing-tools"]), format: nil)
      as! [String: Any]
    let kr = (keep["PayloadContent"] as! [[String: Any]]).first { $0["PayloadType"] as? String == "com.apple.applicationaccess" }!
    check(kr["allowWritingTools"] == nil && kr["allowGenmoji"] as? Bool == false, "a kept feature is left alone")
  } catch {
    check(false, "the profile builds: \(error)")
  }
  print(failed == 0 ? Term.green("all checks passed") : Term.red("\(failed) failed"))
  return failed == 0
}
