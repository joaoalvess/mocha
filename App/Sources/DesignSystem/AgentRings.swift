import MochaProtocol
import SwiftUI

struct AgentRingCounts: Equatable {
    let total: Int
    let blocked: Int
    let working: Int

    init(statuses: [AgentStatus]) {
        total = statuses.count
        blocked = statuses.filter { $0 == .blocked }.count
        working = statuses.filter { $0 == .working }.count
    }

    var blockedFraction: CGFloat {
        total == 0 ? 0 : CGFloat(blocked) / CGFloat(total)
    }

    var workingFraction: CGFloat {
        total == 0 ? 0 : CGFloat(working) / CGFloat(total)
    }

    var accessibilityValue: String {
        "\(blocked) precisam de você, \(working) trabalhando"
    }
}

struct AgentRings: View {
    let counts: AgentRingCounts
    let isOffline: Bool

    private static let lineWidth: CGFloat = 4.3
    private static let outerRadius: CGFloat = 12
    private static let innerRadius: CGFloat = 7.5
    private static let dotDiameter: CGFloat = 10
    private static let dotDistance: CGFloat = 10

    var body: some View {
        ZStack {
            ring(radius: Self.outerRadius, fraction: counts.blockedFraction, track: Palette.ringBlockedTrack, fill: Palette.ringBlocked)
            ring(radius: Self.innerRadius, fraction: counts.workingFraction, track: Palette.ringWorkingTrack, fill: Palette.ringWorking)
            if !isOffline && counts.working > 0 {
                Circle()
                    .fill(Palette.statusOk)
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                    .offset(x: Self.dotDistance * cos(.pi / 4), y: -Self.dotDistance * sin(.pi / 4))
            }
        }
    }

    private func ring(radius: CGFloat, fraction: CGFloat, track: Color, fill: Color) -> some View {
        ZStack {
            Circle()
                .stroke(isOffline ? Palette.offlineRing.opacity(0.5) : track, lineWidth: Self.lineWidth)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: min(fraction, 1))
                    .stroke(isOffline ? Palette.offlineRing : fill, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}
