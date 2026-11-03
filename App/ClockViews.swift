import IpduoClockCore
import SwiftUI

struct ClockScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter

    var body: some View {
        NavigationStack {
            AdaptiveArrangement(style: .split, axes: [.horizontal, .vertical]) {
                FacePager()
                    .duoSplitRatio(0.58)
                    .duoBackgroundExtension()
            } secondary: {
                ClockSideColumn()
            }
            .navigationTitle("Clock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.tap(enabled: model.hapticsEnabled)
                        model.standByPresented = true
                    } label: {
                        Label("StandBy", systemImage: "moon.stars")
                    }
                }
                .duoPriorityHigh()
                ToolbarItem(placement: .automatic) {
                    Button {
                        model.settingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .duoPriorityLow()
            }
        }
    }
}

private struct FacePager: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            StageBackground(tint: model.accentColor)
            TabView(selection: $model.face) {
                AnalogFace().tag(ClockFaceID.analog)
                DigitalFace().tag(ClockFaceID.digital)
                FlipFace().tag(ClockFaceID.flip)
                AmbientFace().tag(ClockFaceID.ambient)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .onChange(of: model.face) { _, _ in
            Haptics.selection(enabled: model.hapticsEnabled)
            model.touch()
        }
    }
}

struct AnalogFace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) * 0.78
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .strokeBorder(model.accentColor.opacity(scheme == .dark ? 0.55 : 0.35), lineWidth: max(1, side * 0.012))
                    tickMarks(side: side)
                    hands(date: context.date, side: side)
                    Circle()
                        .fill(model.accentColor)
                        .frame(width: side * 0.035, height: side * 0.035)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                }
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(context.date, format: .dateTime.hour().minute()))
            }
        }
        .accessibilityIdentifier("face-analog")
    }

    private func tickMarks(side: CGFloat) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2
            for index in 0..<60 {
                let angle = (Double(index) / 60) * .pi * 2 - .pi / 2
                let major = index % 5 == 0
                let outer = radius * 0.9
                let inner = radius * (major ? 0.78 : 0.84)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                context.stroke(
                    path,
                    with: .color(Color.primary.opacity(major ? 0.85 : 0.28)),
                    style: StrokeStyle(lineWidth: major ? radius * 0.012 : radius * 0.006, lineCap: .round)
                )
            }
        }
    }

    private func hands(date: Date, side: CGFloat) -> some View {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1_000_000_000
        let minutes = Double(parts.minute ?? 0) + seconds / 60
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
        return ZStack {
            hand(length: side * 0.26, thickness: side * 0.018, angle: hours / 12 * 360)
            hand(length: side * 0.36, thickness: side * 0.012, angle: minutes / 60 * 360)
            hand(length: side * 0.40, thickness: side * 0.006, angle: seconds / 60 * 360)
                .foregroundStyle(model.accentColor)
        }
    }

    private func hand(length: CGFloat, thickness: CGFloat, angle: Double) -> some View {
        Capsule()
            .frame(width: thickness, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}

struct DigitalFace: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                let width = proxy.size.width
                VStack(spacing: width * 0.03) {
                    Text(ClockFormat.time(from: context.date, use24Hour: model.use24Hour, includingSeconds: false))
                        .font(.system(size: width * 0.22, weight: .thin, design: .default))
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .monospacedDigit()
                    if model.showSeconds {
                        Text(seconds(context.date))
                            .font(.system(size: width * 0.08, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(model.accentColor)
                    }
                    Text(ClockFormat.weekdayDate(context.date))
                        .font(.system(size: max(13, width * 0.04), weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
            }
        }
        .accessibilityIdentifier("face-digital")
    }

    private func seconds(_ date: Date) -> String {
        let second = Calendar.current.component(.second, from: date)
        return String(format: "%02d", second)
    }
}

struct FlipFace: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                let text = ClockFormat.digits(from: context.date, use24Hour: model.use24Hour)
                VStack(spacing: proxy.size.height * 0.04) {
                    HStack(spacing: proxy.size.width * 0.02) {
                        ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                            if character == ":" {
                                Text(":")
                                    .font(.system(size: proxy.size.height * 0.16, weight: .medium, design: .rounded))
                                    .foregroundStyle(model.accentColor)
                                    .frame(width: proxy.size.width * 0.05)
                            } else {
                                FlapDigit(digit: character, accent: model.accentColor)
                            }
                        }
                    }
                    .frame(height: proxy.size.height * 0.34)
                    .padding(.horizontal)
                    Text(ClockFormat.weekdayDate(context.date))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("face-flip")
    }
}

private struct FlapDigit: View {
    var digit: Character
    var accent: Color
    @Environment(\.colorScheme) private var scheme
    @State private var shown: Character
    @State private var angle: Double = 0

    init(digit: Character, accent: Color) {
        self.digit = digit
        self.accent = accent
        _shown = State(initialValue: digit)
    }

    var body: some View {
        GeometryReader { proxy in
            let corner = proxy.size.height * 0.12
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72))
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                Rectangle()
                    .fill(Color.black.opacity(scheme == .dark ? 0.35 : 0.08))
                    .frame(height: 1)
                Text(String(shown))
                    .font(.system(size: proxy.size.height * 0.62, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .onChange(of: digit) { _, newValue in
            guard newValue != shown else { return }
            withAnimation(.easeIn(duration: 0.12)) { angle = -88 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                shown = newValue
                angle = 88
                withAnimation(.easeOut(duration: 0.16)) { angle = 0 }
            }
        }
        .accessibilityLabel(Text(String(digit)))
    }
}

struct AmbientFace: View {
    var showsReadout = true
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { proxy in
                let phase = currentPhase(at: context.date)
                let colors = palette(for: phase)
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(Color.white.opacity(scheme == .dark ? 0.16 : 0.28))
                        .frame(width: proxy.size.width * 0.55, height: proxy.size.width * 0.55)
                        .blur(radius: proxy.size.width * 0.08)
                        .offset(glowOffset(date: context.date, in: proxy.size))
                    if showsReadout {
                    VStack(spacing: proxy.size.height * 0.02) {
                        Text(phase.rawValue.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(ClockFormat.time(from: context.date, use24Hour: model.use24Hour))
                            .font(.system(size: proxy.size.width * 0.16, weight: .thin))
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(ClockFormat.weekdayDate(context.date))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(.horizontal)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .ignoresSafeArea()
        .duoBackgroundExtension()
        .accessibilityIdentifier("face-ambient")
    }

    private func currentPhase(at date: Date) -> Solar.Phase {
        let zone = TimeZone.current
        let city = WorldTime.match(timeZone: zone)
        return Solar.phase(
            at: date,
            timeZone: zone,
            latitude: city?.latitude,
            longitude: city?.longitude
        )
    }

    private func palette(for phase: Solar.Phase) -> [Color] {
        switch phase {
        case .night:
            return [Color(red: 0.05, green: 0.07, blue: 0.16), Color(red: 0.10, green: 0.12, blue: 0.28)]
        case .dawn:
            return [Color(red: 0.96, green: 0.55, blue: 0.42), Color(red: 0.45, green: 0.28, blue: 0.48)]
        case .morning:
            return [Color(red: 0.98, green: 0.78, blue: 0.48), Color(red: 0.45, green: 0.70, blue: 0.82)]
        case .afternoon:
            return [Color(red: 0.33, green: 0.62, blue: 0.86), Color(red: 0.20, green: 0.38, blue: 0.62)]
        case .dusk:
            return [Color(red: 0.86, green: 0.36, blue: 0.42), Color(red: 0.28, green: 0.18, blue: 0.42)]
        }
    }

    private func glowOffset(date: Date, in size: CGSize) -> CGSize {
        let second = Calendar.current.component(.second, from: date)
        let nano = Calendar.current.component(.nanosecond, from: date)
        let turn = (Double(second) + Double(nano) / 1_000_000_000) / 60 * .pi * 2
        return CGSize(width: cos(turn) * size.width * 0.16, height: sin(turn) * size.height * 0.08)
    }
}

struct ClockSideColumn: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if playback.source != .idle {
                    Button {
                        model.tab = .listen
                        model.nowPlayingPresented = true
                    } label: {
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: playback.isPlaying ? "waveform" : "pause.fill")
                                    .foregroundStyle(model.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playback.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(playback.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.forward")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text("World Clock")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("world-clock-heading")
                    .padding(.horizontal, 4)

                HereCard()

                ForEach(model.cities) { city in
                    WorldCityCard(city: city, prominent: false)
                }
            }
            .padding()
        }
        .background(Color.clear)
    }
}

struct HereCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let zone = TimeZone.current
            let match = WorldTime.match(timeZone: zone)
            let day = WorldTime.isDaylight(
                at: context.date,
                timeZone: zone,
                latitude: match?.latitude,
                longitude: match?.longitude
            )
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Here")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(1)
                        Text(match?.name ?? zone.identifier)
                            .font(.title3.weight(.semibold))
                        Text(ClockFormat.time(from: context.date, use24Hour: model.use24Hour))
                            .font(.system(.title, design: .rounded, weight: .light))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Image(systemName: day ? "sun.max.fill" : "moon.stars.fill")
                        .font(.title2)
                        .foregroundStyle(model.accentColor)
                        .accessibilityLabel(day ? "Day" : "Night")
                }
            }
        }
    }
}

struct WorldCityCard: View {
    var city: WorldCity
    var prominent: Bool
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let zone = city.timeZone ?? .current
            let day = WorldTime.isDaylight(
                at: context.date,
                timeZone: zone,
                latitude: city.latitude,
                longitude: city.longitude
            )
            let offset = WorldTime.offset(from: .current, to: zone, at: context.date)
            GlassCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(city.name)
                            .font(prominent ? .title2.weight(.semibold) : .headline)
                        Text(city.region)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(offset.summary)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(ClockFormat.time(from: context.date, use24Hour: model.use24Hour))
                            .font(.system(prominent ? .largeTitle : .title2, design: .rounded, weight: .light))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Image(systemName: day ? "sun.max.fill" : "moon.stars.fill")
                            .foregroundStyle(day ? Color.orange : model.accentColor)
                            .accessibilityLabel(day ? "Day" : "Night")
                    }
                }
            }
        }
    }
}

struct StandByView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AdaptiveArrangement(style: .overlay, axes: [.horizontal, .vertical]) {
            FoldSafeContainer { _ in
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 18) {
                        Text(ClockFormat.time(from: context.date, use24Hour: model.use24Hour, includingSeconds: model.showSeconds))
                            .font(.system(size: 420, weight: .thin))
                            .minimumScaleFactor(0.02)
                            .lineLimit(1)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(ClockFormat.weekdayDate(context.date))
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .textCase(.uppercase)
                            .tracking(1.5)
                        Button {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .accessibilityIdentifier("standby-close")
                        .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } secondary: {
            AmbientFace(showsReadout: false)
        }
        .background(Color.black)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .screenshotMarker()
    }
}
