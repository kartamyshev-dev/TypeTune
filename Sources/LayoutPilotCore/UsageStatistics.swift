import Foundation

/// Counts only; no editor text, clipboard contents, application IDs or timestamps.
public enum UsageCategory: String, Codable, CaseIterable, Sendable {
    case automatic, typo, yo, manual, singleShift, sound
    /// Double Shift and other explicit correction gestures share one category.
    public static let doubleShift: UsageCategory = .manual
    public var secondsPerAction: Int64 {
        switch self {
        case .automatic, .typo: return 10
        case .yo: return 3
        case .manual: return 7
        case .singleShift: return 2
        case .sound: return 1
        }
    }
    public var isCorrection: Bool {
        switch self {
        case .automatic, .typo, .yo, .manual: return true
        case .singleShift, .sound: return false
        }
    }
}

public struct UsageStatistics: Codable, Equatable, Sendable {
    public private(set) var counts: [UsageCategory: Int64] = Dictionary(uniqueKeysWithValues: UsageCategory.allCases.map { ($0, 0) })
    public private(set) var unclassifiedHistorical: Int64
    public init(legacyCorrected: Int64 = 0) {
        unclassifiedHistorical = max(0, legacyCorrected)
    }
    public subscript(_ category: UsageCategory) -> Int64 { counts[category] ?? 0 }
    /// The caller must supply a verified outcome. Attempts/rejections do not count.
    @discardableResult public mutating func record(_ category: UsageCategory, confirmed: Bool) -> Bool {
        guard confirmed, self[category] < Int64.max else { return false }
        counts[category] = self[category] + 1
        return true
    }
    /// Preserve legacy totals updated by an older build without inventing categories.
    @discardableResult public mutating func reconcileLegacyTotal(_ legacy: Int64) -> Bool {
        guard legacy > correctedTotal else { return false }
        unclassifiedHistorical = Self.add(unclassifiedHistorical, legacy - correctedTotal)
        return true
    }
    public var classifiedCorrections: Int64 {
        UsageCategory.allCases.filter(\.isCorrection).reduce(0) { Self.add($0, self[$1]) }
    }
    public var correctedTotal: Int64 { Self.add(unclassifiedHistorical, classifiedCorrections) }
    public func estimatedSeconds(for category: UsageCategory) -> Int64 {
        let (value, overflow) = self[category].multipliedReportingOverflow(by: category.secondsPerAction)
        return overflow ? Int64.max : value
    }
    /// Our own aggregate of action estimates, not proof of an original UI total.
    /// Historical unclassified corrections intentionally receive no time estimate.
    public var estimatedSeconds: Int64 {
        UsageCategory.allCases.reduce(0) { Self.add($0, estimatedSeconds(for: $1)) }
    }
    public static func durationLabel(seconds: Int64) -> String {
        let value = max(0, seconds)
        if value < 60 { return "\(value) с" } // Own display improvement below one minute.
        if value <= 3600 { return "\(value / 60) мин" }
        return "\(value / 3600) ч"
    }
    private static func add(_ left: Int64, _ right: Int64) -> Int64 {
        let (value, overflow) = left.addingReportingOverflow(right)
        return overflow ? Int64.max : value
    }
    private enum CodingKeys: String, CodingKey { case version, counts, unclassifiedHistorical }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported statistics version")
        }
        let history = try values.decode(Int64.self, forKey: .unclassifiedHistorical)
        guard history >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .unclassifiedHistorical, in: values, debugDescription: "Negative historical count")
        }
        let raw = try values.decode([String: Int64].self, forKey: .counts)
        var decoded = Dictionary(uniqueKeysWithValues: UsageCategory.allCases.map { ($0, Int64(0)) })
        for (name, count) in raw {
            guard let category = UsageCategory(rawValue: name), count >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .counts, in: values, debugDescription: "Unknown category or negative count")
            }
            decoded[category] = count
        }
        counts = decoded
        unclassifiedHistorical = history
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .version)
        try values.encode(unclassifiedHistorical, forKey: .unclassifiedHistorical)
        try values.encode(Dictionary(uniqueKeysWithValues: UsageCategory.allCases.map { ($0.rawValue, self[$0]) }), forKey: .counts)
    }
}
