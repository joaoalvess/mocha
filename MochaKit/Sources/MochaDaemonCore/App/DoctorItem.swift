import Foundation

public enum DoctorStatus: Int, Sendable, Comparable {
    case ok
    case warning
    case failure

    public static func < (lhs: DoctorStatus, rhs: DoctorStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var symbol: String {
        switch self {
        case .ok: "✅"
        case .warning: "⚠️"
        case .failure: "❌"
        }
    }
}

public struct DoctorItem: Sendable, Equatable {
    public var title: String
    public var status: DoctorStatus
    public var summary: String
    public var details: [String]

    public init(_ title: String, _ status: DoctorStatus, _ summary: String, details: [String] = []) {
        self.title = title
        self.status = status
        self.summary = summary
        self.details = details
    }
}

public enum DoctorReport {
    public static func render(_ items: [DoctorItem]) -> String {
        items.map { item in
            ([item.status.symbol + " " + item.title + ": " + item.summary] + item.details.map { "   " + $0 }).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    public static func exitCode(_ items: [DoctorItem]) -> Int32 {
        items.contains { $0.status == .failure } ? 1 : 0
    }
}

public enum ElapsedText {
    public static func since(_ start: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 1 {
            return "menos de 1 min"
        }
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) h \(String(format: "%02d", minutes % 60)) min"
        }
        return "\(hours / 24) d \(hours % 24) h"
    }
}
