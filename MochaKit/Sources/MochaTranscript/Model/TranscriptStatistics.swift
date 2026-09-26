import Foundation

public struct TranscriptStatistics: Sendable, Equatable {
    public var dropped: Int
    public var orphanResults: Int
    public var unknown: [String: Int]

    public init(dropped: Int = 0, orphanResults: Int = 0, unknown: [String: Int] = [:]) {
        self.dropped = dropped
        self.orphanResults = orphanResults
        self.unknown = unknown
    }
}
