import Foundation

/// Remembers how far a listener got in an episode.
/// Positions under `minimumKeep` are discarded, and a playhead within
/// `completionMargin` of the end is treated as finished so the next play starts over.
public struct ResumeBook: Equatable {
    public private(set) var positions: [String: TimeInterval]
    public var minimumKeep: TimeInterval
    public var completionMargin: TimeInterval

    public init(
        positions: [String: TimeInterval] = [:],
        minimumKeep: TimeInterval = 2,
        completionMargin: TimeInterval = 3
    ) {
        self.positions = positions
        self.minimumKeep = minimumKeep
        self.completionMargin = completionMargin
    }

    public mutating func record(id: String, seconds: TimeInterval, duration: TimeInterval?) {
        let seconds = max(0, seconds)
        if let duration, duration > 0, seconds >= duration - completionMargin {
            positions.removeValue(forKey: id)
            return
        }
        if seconds < minimumKeep {
            positions.removeValue(forKey: id)
            return
        }
        positions[id] = seconds
    }

    public func position(for id: String) -> TimeInterval {
        max(0, positions[id] ?? 0)
    }

    public func fraction(id: String, duration: TimeInterval?) -> Double? {
        guard let duration, duration > 0 else { return nil }
        let position = position(for: id)
        guard position > 0 else { return nil }
        return min(1, position / duration)
    }
}

public enum PlaybackSkip {
    /// Moves `current` by `delta` seconds and clamps to `0...duration` when duration is known.
    public static func seek(current: TimeInterval, duration: TimeInterval?, delta: TimeInterval) -> TimeInterval {
        var target = max(0, current) + delta
        if target < 0 { target = 0 }
        if let duration, duration.isFinite {
            target = min(max(0, duration), target)
        }
        return target
    }
}

public enum PlaybackRate {
    public static let presets: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]

    public static func clamped(_ value: Float) -> Float {
        min(2, max(0.5, value))
    }

    public static func label(_ value: Float) -> String {
        if abs(value - value.rounded()) < 0.01 {
            return String(format: "%.0f×", value)
        }
        return String(format: "%.2g×", value)
    }
}
