import Foundation

public struct CountdownState: Equatable {
    public var duration: TimeInterval
    public private(set) var isRunning: Bool
    private var endsAt: Date?
    private var pausedRemaining: TimeInterval

    public init(duration: TimeInterval) {
        let safe = max(0, duration)
        self.duration = safe
        isRunning = false
        endsAt = nil
        pausedRemaining = safe
    }

    public func remaining(at now: Date) -> TimeInterval {
        if isRunning, let endsAt {
            return max(0, endsAt.timeIntervalSince(now))
        }
        return max(0, pausedRemaining)
    }

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, duration - remaining(at: now))
    }

    /// 0 when the countdown starts, 1 when it has finished.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed(at: now) / duration))
    }

    public func isFinished(at now: Date) -> Bool {
        duration > 0 && remaining(at: now) <= 0.000_5
    }

    public mutating func start(at now: Date) {
        let remain = remaining(at: now)
        guard remain > 0 else { return }
        isRunning = true
        endsAt = now.addingTimeInterval(remain)
    }

    public mutating func pause(at now: Date) {
        pausedRemaining = remaining(at: now)
        isRunning = false
        endsAt = nil
    }

    public mutating func reset() {
        isRunning = false
        endsAt = nil
        pausedRemaining = duration
    }

    public mutating func setDuration(_ newDuration: TimeInterval) {
        duration = max(0, newDuration)
        if !isRunning {
            pausedRemaining = duration
        }
    }
}

public enum CountdownFormat {
    public static func clock(_ interval: TimeInterval) -> String {
        let remain = max(0, Int(interval.rounded(.up)))
        let hours = remain / 3600
        let minutes = (remain % 3600) / 60
        let seconds = remain % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
