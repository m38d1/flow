import AppKit
import Combine
import Foundation
import ServiceManagement

struct TrafficPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let down: Double
    let up: Double
}

struct InterfaceReading: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let label: String
    let down: Double
    let up: Double
    let isPrimary: Bool
}

final class FlowModel: ObservableObject {
    @Published private(set) var downRate: Double = 0
    @Published private(set) var upRate: Double = 0
    @Published private(set) var history: [TrafficPoint] = []
    @Published private(set) var today = UsageTotals()
    @Published private(set) var month = UsageTotals()
    @Published private(set) var session = UsageTotals()
    @Published private(set) var interfaces: [InterfaceReading] = []
    @Published private(set) var primaryLabel = "No connection"
    @Published private(set) var isOnline = false
    @Published private(set) var menuBarTitle = "↓   0 ↑   0"
    @Published var launchAtLogin = false

    private let sampler = NetworkSampler()
    private let store: UsageStore
    private var usage = UsageAccumulator()
    private var calculators: [String: RateCalculator] = [:]
    private var lastPrimary: (name: String, down: UInt64, up: UInt64)?
    private var timer: DispatchSourceTimer?
    private var dirty = false
    private var lastSave = Date.distantPast
    private let activityToken: NSObjectProtocol
    private var observers: [NSObjectProtocol] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = UsageStore(fileURL: support.appendingPathComponent("Flow/usage.json"))
        usage.restore(days: store.load())
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .background,
            reason: "Flow samples network counters continuously"
        )
        history = (0..<60).map {
            TrafficPoint(timestamp: Date().addingTimeInterval(Double($0) - 59), down: 0, up: 0)
        }
        refreshLoginItem()
        refreshUsage(now: Date())
        start()
    }

    func tick() {
        let snapshot = sampler.snapshot()
        let now = Date()
        var seen = Set<String>()
        var readings: [InterfaceReading] = []

        for item in snapshot.interfaces where item.isUp {
            seen.insert(item.name)
            var calculator = calculators[item.name] ?? RateCalculator()
            let rate = calculator.sample(at: snapshot.timestamp, down: item.down, up: item.up)
            calculators[item.name] = calculator
            let isPrimary = item.name == snapshot.primaryName
            if isPrimary || rate.down > 1 || rate.up > 1 {
                readings.append(InterfaceReading(
                    name: item.name,
                    label: sampler.displayName(for: item.name),
                    down: rate.down,
                    up: rate.up,
                    isPrimary: isPrimary
                ))
            }
        }
        calculators = calculators.filter { seen.contains($0.key) }

        readings.sort { first, second in
            if first.isPrimary != second.isPrimary { return first.isPrimary }
            return first.down + first.up > second.down + second.up
        }

        let primaryReading = readings.first { $0.isPrimary }
        let down = primaryReading?.down ?? 0
        let up = primaryReading?.up ?? 0
        downRate = down
        upRate = up
        history.append(TrafficPoint(timestamp: now, down: down, up: up))
        if history.count > 60 { history.removeFirst(history.count - 60) }

        interfaces = Array(readings.prefix(3))
        isOnline = snapshot.primaryName != nil
        primaryLabel = snapshot.primaryName.map { sampler.displayName(for: $0) } ?? "No connection"

        if let name = snapshot.primaryName, let last = lastPrimary, last.name == name {
            let downBytes = counterDelta(current: snapshot.primaryDown, previous: last.down)
            let upBytes = counterDelta(current: snapshot.primaryUp, previous: last.up)
            if downBytes > 0 || upBytes > 0 {
                usage.add(down: downBytes, up: upBytes, at: now)
                dirty = true
            }
        }
        if let name = snapshot.primaryName {
            lastPrimary = (name, snapshot.primaryDown, snapshot.primaryUp)
        } else {
            lastPrimary = nil
        }

        refreshUsage(now: now)
        updateMenuBarTitle()

        if dirty, now.timeIntervalSince(lastSave) > 5 {
            saveUsage()
        }
    }

    func resetUsage() {
        usage.resetAll()
        dirty = true
        saveUsage()
        refreshUsage(now: Date())
    }

    func flush() {
        guard dirty else { return }
        saveUsage()
    }

    func refreshLoginItem() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Flow: launch-at-login failed: \(error.localizedDescription)")
        }
        refreshLoginItem()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func start() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.2, repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.flush() })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastPrimary = nil
        })
    }

    private func refreshUsage(now: Date) {
        today = usage.totals(on: now)
        month = usage.monthTotals(containing: now)
        session = usage.session
    }

    private func updateMenuBarTitle() {
        let title = "↓\(padded(ByteFormat.compactRate(downRate))) ↑\(padded(ByteFormat.compactRate(upRate)))"
        if title != menuBarTitle {
            menuBarTitle = title
        }
    }

    private func padded(_ value: String) -> String {
        let width = 4
        return value.count >= width ? value : String(repeating: " ", count: width - value.count) + value
    }

    private func saveUsage() {
        do {
            try store.save(usage.days)
            dirty = false
            lastSave = Date()
        } catch {
            NSLog("Flow: could not save usage: \(error.localizedDescription)")
        }
    }
}
