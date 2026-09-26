import Foundation

public enum TurnDuration {
    public static func text(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    public static func text(milliseconds: Int) -> String {
        text(seconds: milliseconds / 1_000)
    }

    public static func text(from start: Date, to end: Date) -> String {
        text(seconds: Int(end.timeIntervalSince(start).rounded(.down)))
    }
}
