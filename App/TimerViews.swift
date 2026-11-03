import IpduoClockCore
import SwiftUI

struct TimersScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    AdaptiveArrangement(style: .split, axes: [.horizontal, .vertical]) {
                        TimerPage()
                    } secondary: {
                        StopwatchPage()
                    }
                } else {
                    VStack(spacing: 0) {
                        Picker("Timer or Stopwatch", selection: $model.timerSegment) {
                            Text("Timer").tag(TimerSegment.timer)
                            Text("Stopwatch").tag(TimerSegment.stopwatch)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        if model.timerSegment == .timer {
                            TimerPage()
                        } else {
                            StopwatchPage()
                        }
                    }
                }
            }
            .background(StageBackground(tint: model.accentColor))
            .navigationTitle("Timers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.timerSegment == .stopwatch || horizontalSizeClass == .regular {
                        Button {
                            Haptics.tap(enabled: model.hapticsEnabled)
                            model.stopwatch.lap(at: Date())
                        } label: {
                            Label("Lap", systemImage: "flag")
                        }
                        .disabled(!model.stopwatch.isRunning && model.stopwatch.elapsed(at: Date()) == 0)
                        Button {
                            Haptics.tap(enabled: model.hapticsEnabled)
                            model.stopwatch.reset()
                        } label: {
                            Label("Reset Stopwatch", systemImage: "arrow.counterclockwise")
                        }
                    }
                    if model.timerSegment == .timer || horizontalSizeClass == .regular {
                        Button {
                            Haptics.tap(enabled: model.hapticsEnabled)
                            model.countdown.reset()
                            model.touch()
                        } label: {
                            Label("Reset Timer", systemImage: "timer")
                        }
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
            .duoPrefersToolbar()
        }
    }
}

private struct TimerPage: View {
    @EnvironmentObject private var model: AppModel
    private let presets: [TimeInterval] = [60, 180, 300, 600, 900, 1800, 3600]

    var body: some View {
        TimelineView(.animation(minimumInterval: model.countdown.isRunning ? 1.0 / 30.0 : nil)) { context in
            let remaining = model.countdown.remaining(at: context.date)
            let progress = model.countdown.progress(at: context.date)
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) * 0.62
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: side * 0.045)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                model.accentColor,
                                style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 4) {
                            Text(CountdownFormat.clock(remaining))
                                .font(.system(size: side * 0.22, weight: .thin, design: .rounded))
                                .minimumScaleFactor(0.4)
                                .lineLimit(1)
                                .monospacedDigit()
                            Text(model.countdown.isRunning ? "Running" : (model.countdown.isFinished(at: context.date) ? "Done" : "Ready"))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(1.2)
                        }
                    }
                    .frame(width: side, height: side)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Timer \(CountdownFormat.clock(remaining))")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { preset in
                                Button {
                                    guard !model.countdown.isRunning else { return }
                                    model.countdown.setDuration(preset)
                                    model.touch()
                                    Haptics.selection(enabled: model.hapticsEnabled)
                                } label: {
                                    Text(presetLabel(preset))
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                                .tint(abs(model.countdown.duration - preset) < 0.5 ? model.accentColor : .secondary)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Button {
                        Haptics.tap(enabled: model.hapticsEnabled)
                        if model.countdown.isRunning {
                            model.countdown.pause(at: Date())
                        } else if model.countdown.isFinished(at: Date()) {
                            model.countdown.reset()
                            model.countdown.start(at: Date())
                        } else {
                            model.countdown.start(at: Date())
                        }
                    } label: {
                        Label(model.countdown.isRunning ? "Pause" : "Start", systemImage: model.countdown.isRunning ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func presetLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "1h"
    }
}

private struct StopwatchPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: model.stopwatch.isRunning ? 1.0 / 30.0 : nil)) { context in
            let elapsed = model.stopwatch.elapsed(at: context.date)
            VStack(spacing: 16) {
                Text(ElapsedFormat.string(from: elapsed))
                    .font(.system(size: 64, weight: .thin, design: .rounded))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .monospacedDigit()
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    Button {
                        Haptics.tap(enabled: model.hapticsEnabled)
                        model.stopwatch.lap(at: Date())
                    } label: {
                        Label("Lap", systemImage: "flag")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(elapsed == 0 && !model.stopwatch.isRunning)
                    Button {
                        Haptics.success(enabled: model.hapticsEnabled)
                        model.stopwatch.toggle(at: Date())
                    } label: {
                        Label(model.stopwatch.isRunning ? "Stop" : "Start", systemImage: model.stopwatch.isRunning ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                List(model.stopwatch.laps) { lap in
                    HStack {
                        Text("Lap \(lap.index)")
                        Spacer(minLength: 8)
                        Text(ElapsedFormat.string(from: lap.split))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(ElapsedFormat.string(from: lap.total))
                            .monospacedDigit()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
