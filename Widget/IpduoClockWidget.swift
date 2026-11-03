import SwiftUI
import WidgetKit

struct ClockEntry: TimelineEntry {
    var date: Date
}

struct ClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockEntry {
        ClockEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ClockEntry) -> Void) {
        completion(ClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let entries = (0..<120).compactMap { minute -> ClockEntry? in
            guard let date = calendar.date(byAdding: .minute, value: minute, to: now) else { return nil }
            return ClockEntry(date: date)
        }
        let refresh = calendar.date(byAdding: .minute, value: 120, to: now) ?? now.addingTimeInterval(7200)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct IpduoClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IpduoClock", provider: ClockProvider()) { entry in
            ClockWidgetView(entry: entry)
        }
        .configurationDisplayName("Ipduo Clock")
        .description("A quiet clock for the Home Screen, Lock Screen, and StandBy.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct ClockWidgetView: View {
    var entry: ClockEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(entry.date, format: .dateTime.hour().minute())
            case .accessoryCircular:
                WidgetAnalog(date: entry.date, showTicks: false)
                    .padding(4)
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    WidgetAnalog(date: entry.date, showTicks: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date, format: .dateTime.hour().minute())
                            .font(.headline)
                            .monospacedDigit()
                        Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .systemMedium:
                HStack(spacing: 12) {
                    WidgetAnalog(date: entry.date, showTicks: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.date, format: .dateTime.hour().minute())
                            .font(.system(.title, design: .rounded, weight: .thin))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(entry.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                VStack(spacing: 6) {
                    WidgetAnalog(date: entry.date, showTicks: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(entry.date, format: .dateTime.hour().minute())
                        .font(.headline.weight(.medium))
                        .monospacedDigit()
                        .widgetAccentable()
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct WidgetAnalog: View {
    var date: Date
    var showTicks: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let minute = Double(parts.minute ?? 0) + Double(parts.second ?? 0) / 60
            let hour = Double((parts.hour ?? 0) % 12) + minute / 60
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, side * 0.02))
                if showTicks {
                    ForEach(0..<12, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: max(1, side * 0.015), height: side * 0.08)
                            .offset(y: -side * 0.36)
                            .rotationEffect(.degrees(Double(index) / 12 * 360))
                    }
                }
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(2, side * 0.03), height: side * 0.24)
                    .offset(y: -side * 0.10)
                    .rotationEffect(.degrees(hour / 12 * 360))
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(1.5, side * 0.02), height: side * 0.34)
                    .offset(y: -side * 0.14)
                    .rotationEffect(.degrees(minute / 60 * 360))
                Circle()
                    .fill(Color(red: 0.45, green: 0.78, blue: 0.72))
                    .frame(width: side * 0.06, height: side * 0.06)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

@main
struct IpduoClockWidgetBundle: WidgetBundle {
    var body: some Widget {
        IpduoClockWidget()
    }
}
