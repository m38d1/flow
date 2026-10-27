import Foundation

var failures = 0
var checks = 0

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL \(name): expected \(expected), got \(actual)  (\(file):\(line))")
    }
}

func expectTrue(_ condition: Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL \(name)  (\(file):\(line))")
    }
}

// MARK: - ByteFormat

expectEqual(ByteFormat.compactRate(0), "0", "compact zero")
expectEqual(ByteFormat.compactRate(-50), "0", "compact negative clamps to zero")
expectEqual(ByteFormat.compactRate(999), "999B", "compact bytes")
expectEqual(ByteFormat.compactRate(1_000), "1.0K", "compact kilobyte")
expectEqual(ByteFormat.compactRate(1_500), "1.5K", "compact one decimal below ten")
expectEqual(ByteFormat.compactRate(24_000), "24K", "compact whole number above ten")
expectEqual(ByteFormat.compactRate(999_999), "1.0M", "compact rounds up across unit")
expectEqual(ByteFormat.compactRate(1_500_000), "1.5M", "compact megabyte")
expectEqual(ByteFormat.compactRate(24_000_000), "24M", "compact whole megabytes")
expectEqual(ByteFormat.compactRate(1_500_000_000), "1.5G", "compact gigabyte")

expectEqual(ByteFormat.rate(0), "0 B/s", "rate zero")
expectEqual(ByteFormat.rate(999), "999 B/s", "rate bytes")
expectEqual(ByteFormat.rate(1_500), "1.5 KB/s", "rate kilobytes")
expectEqual(ByteFormat.rate(24_000_000), "24 MB/s", "rate megabytes")
expectEqual(ByteFormat.rate(999_999), "1.0 MB/s", "rate rounds across unit")

expectEqual(ByteFormat.bytes(0), "0 B", "total zero")
expectEqual(ByteFormat.bytes(999), "999 B", "total bytes")
expectEqual(ByteFormat.bytes(1_500), "1.5 KB", "total kilobytes")
expectEqual(ByteFormat.bytes(340_000_000), "340 MB", "total megabytes")
expectEqual(ByteFormat.bytes(12_400_000_000), "12.4 GB", "total gigabytes")

// MARK: - RateCalculator

var calculator = RateCalculator()
var rates = calculator.sample(at: 0, down: 1_000, up: 500)
expectEqual(rates.down, 0, "first sample has no download rate")
expectEqual(rates.up, 0, "first sample has no upload rate")

rates = calculator.sample(at: 1, down: 1_001_000, up: 50_500)
expectEqual(rates.down, 1_000_000, "download rate over one second")
expectEqual(rates.up, 50_000, "upload rate over one second")

rates = calculator.sample(at: 1.5, down: 1_501_000, up: 50_550)
expectEqual(rates.down, 1_000_000, "download rate over half a second")
expectEqual(rates.up, 100, "upload rate over half a second")

var clockJump = RateCalculator()
_ = clockJump.sample(at: 10, down: 0, up: 0)
rates = clockJump.sample(at: 10, down: 500, up: 500)
expectEqual(rates.down, 0, "zero elapsed returns zero download")
expectEqual(rates.up, 0, "zero elapsed returns zero upload")
rates = clockJump.sample(at: 11, down: 600, up: 700)
expectEqual(rates.down, 100, "zero elapsed sample becomes new baseline")
expectEqual(rates.up, 200, "zero elapsed sample rebaselines upload")

var reset = RateCalculator()
_ = reset.sample(at: 0, down: 1_000_000, up: 1_000_000)
rates = reset.sample(at: 1, down: 500_000, up: 1_200_000)
expectEqual(rates.down, 0, "decreasing counter is treated as reset")
expectEqual(rates.up, 200_000, "other direction still measured on reset")
rates = reset.sample(at: 2, down: 700_000, up: 1_300_000)
expectEqual(rates.down, 200_000, "download measured from post-reset baseline")
expectEqual(rates.up, 100_000, "upload continues after reset")

var backwards = RateCalculator()
_ = backwards.sample(at: 10, down: 0, up: 0)
rates = backwards.sample(at: 9, down: 100, up: 100)
expectEqual(rates.down, 0, "backwards clock returns zero")
rates = backwards.sample(at: 10, down: 300, up: 400)
expectEqual(rates.down, 200, "backwards clock rebaselines download")
expectEqual(rates.up, 300, "backwards clock rebaselines upload")

// MARK: - UsageAccumulator

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(secondsFromGMT: 0)!

func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return utc.date(from: components)!
}

let october27 = makeDate(2026, 10, 27)
let october26 = makeDate(2026, 10, 26)
let november1 = makeDate(2026, 11, 1)

var usage = UsageAccumulator()
usage.add(down: 1_000, up: 200, at: october27, calendar: utc)
expectEqual(usage.totals(on: october27, calendar: utc), UsageTotals(down: 1_000, up: 200), "today totals")
expectEqual(usage.session, UsageTotals(down: 1_000, up: 200), "session totals")

usage.add(down: 500, up: 50, at: october27, calendar: utc)
usage.add(down: 2_000, up: 300, at: october26, calendar: utc)
usage.add(down: 7_000, up: 900, at: november1, calendar: utc)

expectEqual(usage.totals(on: october27, calendar: utc), UsageTotals(down: 1_500, up: 250), "same day accumulates")
expectEqual(usage.totals(on: october26, calendar: utc), UsageTotals(down: 2_000, up: 300), "other day separate")
expectEqual(usage.monthTotals(containing: october27, calendar: utc), UsageTotals(down: 3_500, up: 550), "month sums its days")
expectEqual(usage.monthTotals(containing: november1, calendar: utc), UsageTotals(down: 7_000, up: 900), "next month excludes october")
expectEqual(usage.session, UsageTotals(down: 10_500, up: 1_450), "session spans days")

let monthBoundary = makeDate(2026, 10, 31, 23, 59)
let nextMonth = makeDate(2026, 11, 1, 0, 1)
var boundaryUsage = UsageAccumulator()
boundaryUsage.add(down: 10, up: 1, at: monthBoundary, calendar: utc)
boundaryUsage.add(down: 20, up: 2, at: nextMonth, calendar: utc)
expectEqual(boundaryUsage.monthTotals(containing: monthBoundary, calendar: utc), UsageTotals(down: 10, up: 1), "late night stays in its month")
expectEqual(boundaryUsage.monthTotals(containing: nextMonth, calendar: utc), UsageTotals(down: 20, up: 2), "after midnight moves to next month")

usage.resetAll()
expectEqual(usage.totals(on: october27, calendar: utc), UsageTotals(), "reset clears days")
expectEqual(usage.session, UsageTotals(), "reset clears session")

var restored = UsageAccumulator()
restored.restore(days: ["2026-10-27": UsageTotals(down: 4_000, up: 500)])
expectEqual(restored.totals(on: october27, calendar: utc), UsageTotals(down: 4_000, up: 500), "restored day totals")
expectEqual(restored.session, UsageTotals(), "restore does not invent a session")

// MARK: - UsageStore

let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("flow-tests-\(UUID().uuidString)", isDirectory: true)
let store = UsageStore(fileURL: temporaryRoot.appendingPathComponent("nested/usage.json"))

expectEqual(store.load(), [:], "missing file loads empty usage")

let savedDays = ["2026-10-27": UsageTotals(down: 12_345, up: 678), "2026-10-26": UsageTotals(down: 99, up: 1)]
try store.save(savedDays)
expectEqual(store.load(), savedDays, "usage survives save and load")

try "not json at all".write(to: store.fileURL, atomically: true, encoding: .utf8)
expectEqual(store.load(), [:], "corrupt file loads empty usage")

try? FileManager.default.removeItem(at: temporaryRoot)

// MARK: - counterDelta

expectEqual(counterDelta(current: 100, previous: 40), 60, "counter delta grows")
expectEqual(counterDelta(current: 40, previous: 100), 0, "counter reset yields zero")
expectEqual(counterDelta(current: 0, previous: 0), 0, "counter delta zero")
expectEqual(counterDelta(current: UInt64.max, previous: 0), UInt64.max, "counter delta keeps full range")

// MARK: - Summary

if failures == 0 {
    print("PASS \(checks) checks")
    exit(0)
} else {
    print("FAILED \(failures) of \(checks) checks")
    exit(1)
}
