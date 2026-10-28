import AppKit
import SwiftUI
import WidgetKit

private let downColor = Color(red: 0.20, green: 0.47, blue: 0.98)
private let upColor = Color(red: 0.02, green: 0.66, blue: 0.53)

struct FlowEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct FlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowEntry {
        FlowEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowEntry) -> Void) {
        completion(FlowEntry(date: Date(), snapshot: context.isPreview ? .preview : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [FlowEntry(date: now, snapshot: load())], policy: .after(next)))
    }

    private func load() -> WidgetSnapshot? {
        WidgetSnapshotStore(fileURL: WidgetSnapshotStore.defaultURL).load()
    }
}

private extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        timestamp: Date().timeIntervalSince1970,
        down: 1_240_000,
        up: 84_000,
        today: UsageTotals(down: 4_300_000_000, up: 640_000_000),
        month: UsageTotals(down: 42_000_000_000, up: 6_100_000_000),
        label: "Wi-Fi",
        isOnline: true
    )
}

struct FlowWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FlowEntry

    var body: some View {
        if #available(macOS 14.0, *) {
            content.containerBackground(for: .widget) { background }
        } else {
            content.background(background)
        }
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [downColor.opacity(0.10), Color.clear, upColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 10 : 7) {
            header

            if let snapshot = entry.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    rate(icon: "arrow.down", value: snapshot.down, color: downColor)
                    rate(icon: "arrow.up", value: snapshot.up, color: upColor)
                }
                .padding(.top, 2)

                Divider().opacity(0.3)

                HStack(alignment: .top, spacing: 14) {
                    usage(title: "Today", totals: snapshot.today)
                    usage(title: "This month", totals: snapshot.month)
                }

                Spacer(minLength: 0)

                Text("Updated \(updatedText(snapshot.timestamp))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                Spacer(minLength: 0)
                Text("Open Flow to start measuring.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("Flow")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer(minLength: 4)
            Circle()
                .fill(entry.snapshot?.isOnline == true ? upColor : Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
            Text(entry.snapshot?.label ?? "Offline")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func rate(icon: String, value: Double, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(ByteFormat.rate(value))
                .font(.system(size: family == .systemMedium ? 19 : 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func usage(title: String, totals: UsageTotals) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(ByteFormat.bytes(Double(totals.total)))
                .font(.system(size: family == .systemMedium ? 14 : 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func updatedText(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

struct FlowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlowWidget", provider: FlowProvider()) { entry in
            FlowWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Flow")
        .description("Live network speed and data usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlowWidget()
    }
}
