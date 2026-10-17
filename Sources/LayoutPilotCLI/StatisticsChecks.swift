import Foundation
import LayoutPilotCore

func statisticsChecks() -> [(Bool, String)] {
    var results: [(Bool, String)] = []
    func check(_ value: Bool, _ name: String) { results.append((value, "statistics: " + name)) }
    func decode(_ counts: String, history: String = "0", version: String = "1") -> UsageStatistics? {
        try? JSONDecoder().decode(UsageStatistics.self, from: Data("{\"version\":\(version),\"counts\":\(counts),\"unclassifiedHistorical\":\(history)}".utf8))
    }
    let weights: [(UsageCategory, Int64)] = [(.automatic,10),(.typo,10),(.yo,3),(.manual,7),(.singleShift,2),(.sound,1)]
    var usage = UsageStatistics(legacyCorrected: 19)
    check(usage.correctedTotal == 19 && usage.estimatedSeconds == 0 && usage.classifiedCorrections == 0,
          "legacy totals have no invented categories or saved-time weights")
    check(UsageStatistics(legacyCorrected: -1).unclassifiedHistorical == 0, "negative legacy count is bounded")
    for (category, weight) in weights {
        let before = usage
        check(!usage.record(category, confirmed: false) && usage == before, "failed \(category.rawValue) action changes nothing")
        check(usage.record(category, confirmed: true) && usage[category] == 1, "verified \(category.rawValue) action counts once")
        check(usage.estimatedSeconds(for: category) == weight, "compiled default weight \(category.rawValue)")
    }
    check(usage.classifiedCorrections == 4 && usage.correctedTotal == 23, "source changes and sounds never inflate corrected total")
    check(usage.estimatedSeconds == 33, "own sum includes known action estimates only")
    check(UsageCategory.doubleShift == .manual, "Double Shift and manual correction share a count")
    if let data = try? JSONEncoder().encode(usage), let restored = try? JSONDecoder().decode(UsageStatistics.self, from: data) {
        check(restored == usage, "Codable roundtrip preserves every count and historical total")
        let keys = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        check(Set(keys?.keys.map { $0 } ?? []) == Set(["version","counts","unclassifiedHistorical"]), "stored schema contains only counts and version")
    } else { check(false, "Codable roundtrip") }
    check(decode("{}") == UsageStatistics(), "missing category count means zero")
    var partial = UsageStatistics(legacyCorrected: 4)
    partial.record(.yo, confirmed: true)
    if let data = try? JSONEncoder().encode(partial), let restored = try? JSONDecoder().decode(UsageStatistics.self, from: data) {
        check(restored == partial && restored[.automatic] == 0, "partial-category restart preserves zero-count equality")
    } else { check(false, "partial-category Codable roundtrip") }

    for counts in ["{\"automatic\":-1}", "{\"automatic\":1.25}", "{\"automatic\":\"3\"}", "{\"automatic\":true}",
                   "{\"unknown\":1}", "{\"manual\":9223372036854775808}", "null"] {
        check(decode(counts) == nil, "malformed category counts are rejected: \(counts)")
    }
    check(decode("{}", history: "-1") == nil, "negative historical count rejected")
    check(decode("{}", version: "2") == nil, "unknown storage version rejected")
    if var full = decode("{\"automatic\":9223372036854775807,\"sound\":9223372036854775807}", history: "10") {
        check(!full.record(.automatic, confirmed: true) && full[.automatic] == Int64.max, "count saturates instead of overflowing")
        check(full.correctedTotal == Int64.max && full.estimatedSeconds == Int64.max, "sum and time multiplication saturate")
        check(!full.reconcileLegacyTotal(Int64.max), "saturated total cannot acquire fictional history")
    } else { check(false, "overflow fixture decode") }
    var merged = UsageStatistics(legacyCorrected: 5)
    merged.record(.manual, confirmed: true)
    check(merged.reconcileLegacyTotal(9) && merged.unclassifiedHistorical == 8 && merged[.manual] == 1,
          "newer legacy total preserves difference without assigning categories")
    check(!merged.reconcileLegacyTotal(4) && merged.correctedTotal == 9, "older legacy total never resets saved statistics")
    for (seconds, label) in [(Int64(-1),"0 с"),(0,"0 с"),(59,"59 с"),(60,"1 мин"),(3599,"59 мин"),(3600,"60 мин"),(3601,"1 ч")] {
        check(UsageStatistics.durationLabel(seconds: seconds) == label, "duration boundary \(seconds)")
    }
    return results
}
