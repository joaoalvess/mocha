import Foundation

public enum RelativeTime {
    public static func text(from date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<minute:
            return "agora"
        case ..<hour:
            return "há \(seconds / minute) min"
        case ..<day:
            return "há \(seconds / hour) h"
        case ..<(2 * day):
            return "ontem"
        default:
            return "há \(seconds / day) dias"
        }
    }

    private static let minute = 60
    private static let hour = 60 * minute
    private static let day = 24 * hour
}
