#if DEBUG
import Darwin
import os
import SwiftUI
import UIKit

struct MarkdownPerformanceSample: Sendable {
    let parse: Duration
    let layout: Duration
    let cpu: Duration

    var total: Duration { parse + layout }
}

struct MarkdownPerformanceReport: Sendable {
    let bytes: Int
    let blockCount: Int
    let width: CGFloat
    let samples: [MarkdownPerformanceSample]

    static let budget = Duration.milliseconds(16)

    var cold: Duration { samples.first?.total ?? .zero }
    var warm: [MarkdownPerformanceSample] { Array(samples.dropFirst()) }
    var warmMedian: Duration { Self.percentile(warm.map(\.total), 0.5) }
    var warmP90: Duration { Self.percentile(warm.map(\.total), 0.9) }
    var warmMax: Duration { warm.map(\.total).max() ?? .zero }
    var parseMedian: Duration { Self.percentile(warm.map(\.parse), 0.5) }
    var layoutMedian: Duration { Self.percentile(warm.map(\.layout), 0.5) }
    var cpuMedian: Duration { Self.percentile(warm.map(\.cpu), 0.5) }
    var passes: Bool { warmMedian < Self.budget }

    static func percentile(_ values: [Duration], _ fraction: Double) -> Duration {
        guard !values.isEmpty else { return .zero }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }

    static func milliseconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2f", seconds * 1000)
    }

    var summary: String {
        let ms = Self.milliseconds
        return "bytes=\(bytes) blocks=\(blockCount) width=\(Int(width)) runs=\(samples.count) cold=\(ms(cold))ms median=\(ms(warmMedian))ms p90=\(ms(warmP90))ms max=\(ms(warmMax))ms parseMedian=\(ms(parseMedian))ms layoutMedian=\(ms(layoutMedian))ms cpuMedian=\(ms(cpuMedian))ms budget=16ms verdict=\(passes ? "PASS" : "FAIL")"
    }
}

@MainActor
enum MarkdownPerformanceProbe {
    static let logger = Logger(subsystem: MarkdownSignposts.subsystem, category: "markdown-perf")
    static let signposter = OSSignposter(subsystem: MarkdownSignposts.subsystem, category: "markdown-perf")

    static func run(markdown: String, metrics: MarkdownMetrics, width: CGFloat, iterations: Int) async -> MarkdownPerformanceReport {
        let clock = ContinuousClock()
        var samples: [MarkdownPerformanceSample] = []
        var blockCount = 0
        for iteration in 0..<iterations {
            let id = signposter.makeSignpostID()
            let totalState = signposter.beginInterval("parse+layout", id: id, "run \(iteration)")
            let cpuStart = threadCPUTime()
            let start = clock.now
            let parseState = signposter.beginInterval("parse", id: id)
            let document = MarkdownParser.parse(markdown, metrics: metrics)
            signposter.endInterval("parse", parseState)
            let parsed = clock.now
            let layoutState = signposter.beginInterval("layout", id: id)
            let host = UIHostingController(rootView: MarkdownDocumentView(document: document, metrics: metrics))
            let size = host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
            host.view.layoutIfNeeded()
            signposter.endInterval("layout", layoutState)
            let end = clock.now
            let cpuEnd = threadCPUTime()
            signposter.endInterval("parse+layout", totalState)
            samples.append(MarkdownPerformanceSample(
                parse: start.duration(to: parsed),
                layout: parsed.duration(to: end),
                cpu: .nanoseconds(Int64(cpuEnd - cpuStart))
            ))
            blockCount = document.blocks.count
            await Task.yield()
        }
        let report = MarkdownPerformanceReport(bytes: markdown.utf8.count, blockCount: blockCount, width: width, samples: samples)
        logger.notice("markdown-perf \(report.summary, privacy: .public)")
        return report
    }

    private static func threadCPUTime() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }
}

struct MarkdownPreviewPerformance: View {
    static let iterations = 30
    static let width: CGFloat = 358

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var report: MarkdownPerformanceReport?

    var body: some View {
        let metrics = MarkdownDocumentCache.shared.metrics(for: dynamicTypeSize)
        ZStack(alignment: .topLeading) {
            Palette.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Markdown · parse + layout")
                    .markdownText(metrics.heading, face: .bold)
                if let report {
                    ForEach(lines(report), id: \.self) { line in
                        Text(verbatim: line)
                            .markdownText(metrics.table)
                    }
                    Text(verbatim: report.passes ? "Dentro de 16 ms" : "Acima de 16 ms")
                        .markdownText(metrics.body, face: .bold)
                        .foregroundStyle(report.passes ? Palette.statusOk : Palette.error)
                } else {
                    Text(verbatim: "Medindo…")
                        .markdownText(metrics.body)
                }
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(Metrics.contentMargin)
        }
        .task {
            report = await MarkdownPerformanceProbe.run(
                markdown: MarkdownPreviewSamples.largeMessage(),
                metrics: metrics,
                width: Self.width,
                iterations: Self.iterations
            )
        }
    }

    private func lines(_ report: MarkdownPerformanceReport) -> [String] {
        let ms = MarkdownPerformanceReport.milliseconds
        return [
            "mensagem: \(report.bytes) bytes, \(report.blockCount) blocos",
            "largura: \(Int(report.width)) pt, \(report.samples.count) execuções",
            "fria: \(ms(report.cold)) ms",
            "mediana: \(ms(report.warmMedian)) ms",
            "p90: \(ms(report.warmP90)) ms",
            "máximo: \(ms(report.warmMax)) ms",
            "parse (mediana): \(ms(report.parseMedian)) ms",
            "layout (mediana): \(ms(report.layoutMedian)) ms",
            "CPU da thread (mediana): \(ms(report.cpuMedian)) ms",
        ]
    }
}
#endif
