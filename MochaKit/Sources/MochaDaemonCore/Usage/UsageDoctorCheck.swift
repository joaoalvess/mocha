import Foundation
import MochaProtocol

extension DoctorChecks {
    public static func usage(_ paths: DaemonPaths, now: Date) -> DoctorItem {
        let file = paths.usageCacheFile
        let display = paths.display(file)
        guard UsageFileStamp.of(file) != nil else {
            return DoctorItem("Uso", .warning, "sem o cache do plugin herdr-agent-usage", details: ["esperado em \(display)"])
        }
        guard let cache = StatuslineCache.read(file) else {
            return DoctorItem("Uso", .warning, "cache do plugin herdr-agent-usage inválido", details: [display])
        }
        var summary = "cache atualizado há \(ElapsedText.since(cache.fetchedAt, now: now))"
        for window in cache.windows {
            summary += " · \(label(window.kind)) \(Int(window.usedPercent.rounded()))%"
        }
        return DoctorItem("Uso", .ok, summary, details: [display])
    }

    private static func label(_ kind: UsageWindowKind) -> String {
        switch kind {
        case .fiveHour: "5h"
        case .weekly: "7d"
        case .unknown: "?"
        }
    }
}
