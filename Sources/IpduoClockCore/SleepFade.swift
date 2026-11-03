import Foundation

/// A sleep timer that holds full volume, then fades linearly to silence.
public struct SleepFade: Equatable {
    public static let defaultFadeDuration: TimeInterval = 20

    public var startedAt: Date
    public var duration: TimeInterval
    public var fadeDuration: TimeInterval

    public enum Phase: Equatable {
        case holding(volume: Double, remaining: TimeInterval)
        case fading(volume: Double, remaining: TimeInterval)
        case finished
    }

    public init(startedAt: Date, duration: TimeInterval, fadeDuration: TimeInterval = SleepFade.defaultFadeDuration) {
        self.startedAt = startedAt
        self.duration = max(0, duration)
        self.fadeDuration = max(0, fadeDuration)
    }

    public func phase(at now: Date) -> Phase {
        let remaining = duration - now.timeIntervalSince(startedAt)
        if remaining <= 0 { return .finished }
        let fade = min(fadeDuration, duration)
        if fade <= 0 || remaining > fade {
            return .holding(volume: 1, remaining: remaining)
        }
        let volume = min(1, max(0, remaining / fade))
        return .fading(volume: volume, remaining: remaining)
    }

    public func volume(at now: Date) -> Double {
        switch phase(at: now) {
        case .holding(let volume, _), .fading(let volume, _):
            return volume
        case .finished:
            return 0
        }
    }

    public func isFinished(at now: Date) -> Bool {
        if case .finished = phase(at: now) { return true }
        return false
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, duration - now.timeIntervalSince(startedAt))
    }
}
