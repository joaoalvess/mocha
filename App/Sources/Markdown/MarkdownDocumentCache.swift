import os
import SwiftUI

enum MarkdownSignposts {
    static let subsystem = "com.joaoalves.mocha"
    static let signposter = OSSignposter(subsystem: subsystem, category: "markdown")
}

@MainActor
final class MarkdownDocumentCache {
    private struct Key: Hashable {
        let markdown: String
        let dynamicTypeSize: DynamicTypeSize
    }

    static let shared = MarkdownDocumentCache()

    private let capacity: Int
    private var documents: [Key: MarkdownDocument] = [:]
    private var insertionOrder: [Key] = []
    private var metricsBySize: [DynamicTypeSize: MarkdownMetrics] = [:]

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    func metrics(for dynamicTypeSize: DynamicTypeSize) -> MarkdownMetrics {
        if let cached = metricsBySize[dynamicTypeSize] {
            return cached
        }
        let metrics = MarkdownMetrics(dynamicTypeSize: dynamicTypeSize)
        metricsBySize[dynamicTypeSize] = metrics
        return metrics
    }

    func document(for markdown: String, metrics: MarkdownMetrics) -> MarkdownDocument {
        let key = Key(markdown: markdown, dynamicTypeSize: metrics.dynamicTypeSize)
        if let cached = documents[key] {
            return cached
        }
        let document = Self.parse(markdown, metrics: metrics)
        documents[key] = document
        insertionOrder.append(key)
        if insertionOrder.count > capacity {
            documents[insertionOrder.removeFirst()] = nil
        }
        return document
    }

    static func parse(_ markdown: String, metrics: MarkdownMetrics) -> MarkdownDocument {
        let signposter = MarkdownSignposts.signposter
        let state = signposter.beginInterval("parse", id: signposter.makeSignpostID(), "\(markdown.utf8.count) bytes")
        defer { signposter.endInterval("parse", state) }
        return MarkdownParser.parse(markdown, metrics: metrics)
    }
}
