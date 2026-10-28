import Foundation

enum ByteFormat {
    private static let compactUnits: [(scale: Double, suffix: String)] = [
        (1_000_000_000, "G"),
        (1_000_000, "M"),
        (1_000, "K"),
    ]

    private static let rateUnits: [(scale: Double, suffix: String)] = [
        (1_000_000_000, "GB/s"),
        (1_000_000, "MB/s"),
        (1_000, "KB/s"),
    ]

    private static let totalUnits: [(scale: Double, suffix: String)] = [
        (1_000_000_000, "GB"),
        (1_000_000, "MB"),
        (1_000, "KB"),
    ]

    static func compactRate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        guard value >= 1 else { return "0" }
        guard value >= 1_000 else { return "\(Int(value.rounded()))B" }
        return scaled(value, units: compactUnits, separator: "")
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        guard value >= 1_000 else { return "\(Int(value.rounded())) B/s" }
        return scaled(value, units: rateUnits, separator: " ")
    }

    static func bytes(_ count: Double) -> String {
        let value = max(0, count)
        guard value >= 1_000 else { return "\(Int(value.rounded())) B" }
        return scaled(value, units: totalUnits, separator: " ", decimalBelow: 100)
    }

    private static func scaled(
        _ value: Double,
        units: [(scale: Double, suffix: String)],
        separator: String,
        decimalBelow: Double = 10
    ) -> String {
        for (index, unit) in units.enumerated() where value >= unit.scale {
            let scaled = value / unit.scale
            if scaled >= 999.5, index > 0 {
                let bigger = units[index - 1]
                return human(value / bigger.scale, decimalBelow: decimalBelow) + separator + bigger.suffix
            }
            return human(scaled, decimalBelow: decimalBelow) + separator + unit.suffix
        }
        return "0"
    }

    private static func human(_ value: Double, decimalBelow: Double = 10) -> String {
        value < decimalBelow
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
    }
}

struct CounterSample: Equatable {
    var timestamp: TimeInterval
    var down: UInt64
    var up: UInt64
}

struct RateCalculator {
    private var previous: CounterSample?

    mutating func sample(at timestamp: TimeInterval, down: UInt64, up: UInt64) -> (down: Double, up: Double) {
        let current = CounterSample(timestamp: timestamp, down: down, up: up)
        defer { previous = current }

        guard let last = previous else { return (0, 0) }
        let elapsed = timestamp - last.timestamp
        guard elapsed > 0 else { return (0, 0) }

        let downDelta = down >= last.down ? Double(down - last.down) : 0
        let upDelta = up >= last.up ? Double(up - last.up) : 0
        return (downDelta / elapsed, upDelta / elapsed)
    }
}

struct UsageTotals: Codable, Equatable {
    var down: UInt64 = 0
    var up: UInt64 = 0
    var total: UInt64 { down + up }
}

struct UsageAccumulator: Equatable {
    private(set) var days: [String: UsageTotals] = [:]
    private(set) var session = UsageTotals()

    mutating func add(down: UInt64, up: UInt64, at date: Date, calendar: Calendar = .current) {
        let key = dayKey(date, calendar)
        var totals = days[key] ?? UsageTotals()
        totals.down += down
        totals.up += up
        days[key] = totals
        session.down += down
        session.up += up
    }

    func totals(on date: Date, calendar: Calendar = .current) -> UsageTotals {
        days[dayKey(date, calendar)] ?? UsageTotals()
    }

    func monthTotals(containing date: Date, calendar: Calendar = .current) -> UsageTotals {
        let prefix = monthKey(date, calendar)
        return days.reduce(into: UsageTotals()) { result, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            result.down += entry.value.down
            result.up += entry.value.up
        }
    }

    mutating func restore(days: [String: UsageTotals]) {
        self.days = days
    }

    mutating func resetAll() {
        days.removeAll()
        session = UsageTotals()
    }

    private func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func monthKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

struct UsageStore {
    private struct Payload: Codable {
        var version = 1
        var days: [String: UsageTotals]
    }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [String: UsageTotals] {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return [:]
        }
        return payload.days
    }

    func save(_ days: [String: UsageTotals]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(Payload(days: days))
        try data.write(to: fileURL, options: .atomic)
    }
}

func counterDelta(current: UInt64, previous: UInt64) -> UInt64 {
    current >= previous ? current - previous : 0
}

struct WidgetSnapshot: Codable, Equatable {
    var timestamp: TimeInterval
    var down: Double
    var up: Double
    var today: UsageTotals
    var month: UsageTotals
    var label: String
    var isOnline: Bool
}

struct WidgetSnapshotStore {
    let fileURL: URL

    // Inside the sandboxed widget FileManager homes point at the container, so the
    // real user folder comes from the password database instead.
    static var defaultURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Flow/widget.json")
    }

    func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
