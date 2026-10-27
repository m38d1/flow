import AppKit
import Charts
import SwiftUI

private let downColor = Color(red: 0.20, green: 0.47, blue: 0.98)
private let upColor = Color(red: 0.02, green: 0.66, blue: 0.53)

struct PopoverView: View {
    @ObservedObject var model: FlowModel
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            speedRow
            chartBlock
            usageRow
            sessionRow
            interfacesBlock
            Divider().opacity(0.35)
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(width: 344, height: 532, alignment: .top)
        .background(
            ZStack {
                Rectangle().fill(.thinMaterial)
                LinearGradient(
                    colors: [downColor.opacity(0.075), Color.clear, upColor.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .alert("Reset usage data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetUsage() }
        } message: {
            Text("Today and this month totals will be cleared. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Flow")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isOnline ? upColor : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(model.primaryLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(upColor)
                    .frame(width: 4, height: 4)
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    private var speedRow: some View {
        HStack(alignment: .top, spacing: 14) {
            SpeedMetric(title: "Download", value: ByteFormat.rate(model.downRate), icon: "arrow.down", color: downColor)
            SpeedMetric(title: "Upload", value: ByteFormat.rate(model.upRate), icon: "arrow.up", color: upColor)
        }
    }

    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 60 seconds")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            chartRow(title: "Download", icon: "arrow.down", color: downColor, peak: downPeak, series: \.down)
            chartRow(title: "Upload", icon: "arrow.up", color: upColor, peak: upPeak, series: \.up)
        }
        .padding(10)
        .glassCard()
    }

    private func chartRow(
        title: String,
        icon: String,
        color: Color,
        peak: Double,
        series: KeyPath<TrafficPoint, Double>
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(peak > 0 ? "peak \(ByteFormat.compactRate(peak))" : "idle")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 68, alignment: .leading)

            Chart(model.history) { point in
                AreaMark(
                    x: .value("Second", point.timestamp),
                    y: .value(title, point[keyPath: series])
                )
                .foregroundStyle(LinearGradient(
                    colors: [color.opacity(0.30), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Second", point.timestamp),
                    y: .value(title, point[keyPath: series])
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...max(peak * 1.2, 1024))
            .frame(height: 42)
        }
    }

    private var usageRow: some View {
        HStack(spacing: 8) {
            UsageCard(title: "Today", totals: model.today)
            UsageCard(title: "This month", totals: model.month)
        }
    }

    private var sessionRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text("This session")
                .font(.system(size: 10))
            Spacer()
            Text("↓ \(ByteFormat.bytes(Double(model.session.down)))   ↑ \(ByteFormat.bytes(Double(model.session.up)))   ·   \(ByteFormat.bytes(Double(model.session.total)))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.tertiary)
    }

    private var interfacesBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Interfaces")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            if model.interfaces.isEmpty {
                Text("No active network connection")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.interfaces.prefix(2))) { reading in
                    interfaceRow(reading)
                }
            }
        }
    }

    private func interfaceRow(_ reading: InterfaceReading) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(reading.isPrimary ? upColor : Color.secondary.opacity(0.35))
                .frame(width: 5, height: 5)
            Text(reading.label)
                .font(.system(size: 11, weight: .medium))
            Text(reading.name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            if reading.isPrimary {
                Text("ACTIVE")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(upColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(upColor.opacity(0.12)))
            }
            Spacer(minLength: 8)
            Text("↓ \(ByteFormat.compactRate(reading.down))  ↑ \(ByteFormat.compactRate(reading.up))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Toggle(isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            )) {
                Text("Launch at Login")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack {
                Button {
                    confirmReset = true
                } label: {
                    Label("Reset usage", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.quit()
                } label: {
                    Label("Quit Flow", systemImage: "power")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button {
                if let url = URL(string: "https://github.com/m38d1/flow") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                    Text("github.com/m38d1/flow")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help("Open the Flow repository on GitHub")
        }
    }

    private var downPeak: Double {
        model.history.reduce(0) { max($0, $1.down) }
    }

    private var upPeak: Double {
        model.history.reduce(0) { max($0, $1.up) }
    }
}

private struct SpeedMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageCard: View {
    let title: String
    let totals: UsageTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(ByteFormat.bytes(Double(totals.total)))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("↓ \(ByteFormat.bytes(Double(totals.down)))   ↑ \(ByteFormat.bytes(Double(totals.up)))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 13) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }
}
