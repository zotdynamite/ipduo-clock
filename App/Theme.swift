import SwiftUI
import UIKit

extension AccentPalette {
    var color: Color {
        let components = rgb
        return Color(.sRGB, red: components.red, green: components.green, blue: components.blue)
    }
}

extension AppModel {
    var accentColor: Color { accent.color }

    var preferredScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct StageBackground: View {
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let glow = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.08, green: 0.08, blue: 0.10), Color(red: 0.02, green: 0.02, blue: 0.025)]
                        : [Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.92, green: 0.90, blue: 0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(tint.opacity(scheme == .dark ? 0.28 : 0.18))
                    .frame(width: glow * 0.85, height: glow * 0.85)
                    .blur(radius: glow * 0.18)
                    .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.12)
                Circle()
                    .fill(tint.opacity(scheme == .dark ? 0.14 : 0.10))
                    .frame(width: glow * 0.7, height: glow * 0.7)
                    .blur(radius: glow * 0.16)
                    .position(x: proxy.size.width * 0.88, y: proxy.size.height * 0.78)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

enum Haptics {
    static func tap(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection(enabled: Bool) {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

enum ClockFormat {
    static func time(from date: Date, use24Hour: Bool, includingSeconds: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = Calendar.current
        let template = includingSeconds
            ? (use24Hour ? "HHmmss" : "hmmss")
            : (use24Hour ? "HHmm" : "hmm")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func digits(from date: Date, use24Hour: Bool) -> String {
        var calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let shownHour = use24Hour ? hour : {
            let wrapped = hour % 12
            return wrapped == 0 ? 12 : wrapped
        }()
        if use24Hour {
            return String(format: "%02d:%02d", hour, minute)
        }
        return String(format: "%d:%02d", shownHour, minute)
    }

    static func weekdayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }

    static func hourMinute(hour: Int, minute: Int, use24Hour: Bool) -> String {
        var calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return time(from: date, use24Hour: use24Hour)
    }
}
