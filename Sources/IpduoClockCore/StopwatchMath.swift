import Foundation

public struct StopwatchLap: Equatable, Identifiable {
    public var index: Int
    public var split: TimeInterval
    public var total: TimeInterval

    public var id: Int { index }

    public init(index: Int, split: TimeInterval, total: TimeInterval) {
        self.index = index
        self.split = split
        self.total = total
    }
}

public struct StopwatchState: Equatable {
    public private(set) var isRunning: Bool
    public private(set) var accumulated: TimeInterval
    public private(set) var startedAt: Date?
    public private(set) var laps: [StopwatchLap]
    private var lastLapTotal: TimeInterval

    public init() {
        isRunning = false
        accumulated = 0
        startedAt = nil
        laps = []
        lastLapTotal = 0
    }

    public func elapsed(at now: Date) -> TimeInterval {
        let running = isRunning ? now.timeIntervalSince(startedAt ?? now) : 0
        return max(0, accumulated + running)
    }

    public mutating func start(at now: Date) {
        guard !isRunning else { return }
        isRunning = true
        startedAt = now
    }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: now)
        isRunning = false
        startedAt = nil
    }

    public mutating func toggle(at now: Date) {
        if isRunning {
            pause(at: now)
        } else {
            start(at: now)
        }
    }

    public mutating func lap(at now: Date) {
        let total = elapsed(at: now)
        let split = max(0, total - lastLapTotal)
        lastLapTotal = total
        laps.insert(StopwatchLap(index: laps.count + 1, split: split, total: total), at: 0)
    }

    public mutating func reset() {
        self = StopwatchState()
    }
}

public enum ElapsedFormat {
    public static func string(from interval: TimeInterval, showsHours: Bool = true) -> String {
        let clamped = max(0, interval)
        let totalCentiseconds = Int((clamped * 100).rounded())
        let centiseconds = totalCentiseconds % 100
        let totalSeconds = totalCentiseconds / 100
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if showsHours && hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
        }
        return String(format: "%02d:%02d.%02d", minutes + (showsHours ? 0 : hours * 60), seconds, centiseconds)
    }
}
