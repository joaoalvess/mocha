import MochaProtocol
import SwiftUI

struct AgentRingCounts: Equatable {
    static let autoCapacity = 5
    static let planCapacity = 4
    static let planMode = "plan"
    static let autoModes: Set<String> = ["auto", "acceptEdits", "bypassPermissions"]

    let auto: Int
    let plan: Int
    let working: Int
    let blocked: Int

    init(agents: [AgentSummary]) {
        let modes = agents.filter { $0.kind == AgentKind.claude }.compactMap(\.permissionMode)
        auto = modes.filter { Self.autoModes.contains($0) }.count
        plan = modes.filter { $0 == Self.planMode }.count
        working = agents.filter { $0.status == .working }.count
        blocked = agents.filter { $0.status == .blocked }.count
    }

    var autoFraction: CGFloat {
        CGFloat(min(auto, Self.autoCapacity)) / CGFloat(Self.autoCapacity)
    }

    var planFraction: CGFloat {
        CGFloat(min(plan, Self.planCapacity)) / CGFloat(Self.planCapacity)
    }

    var activity: AgentRingActivity? {
        if blocked > 0 { return .needsYou }
        if working > 0 { return .working }
        return nil
    }

    var accessibilityValue: String {
        "\(blocked) precisam de você, \(working) trabalhando, \(auto) em modo auto, \(plan) em modo plan"
    }
}

enum AgentRingActivity: Equatable {
    case working
    case needsYou

    var color: Color {
        switch self {
        case .working: Palette.statusOk
        case .needsYou: Palette.dirty
        }
    }
}

struct AgentRings: View {
    let counts: AgentRingCounts
    let isOffline: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lineWidth: CGFloat = 4.3
    private static let outerRadius: CGFloat = 12
    private static let innerRadius: CGFloat = 7.5
    private static let dotDiameter: CGFloat = 6
    private static let pulsePeriod: Double = 1.4
    private static let minimumPulseOpacity: Double = 0.3

    var body: some View {
        ZStack {
            ring(radius: Self.outerRadius, fraction: counts.autoFraction, track: Palette.ringAutoTrack, fill: Palette.ringAuto)
            ring(radius: Self.innerRadius, fraction: counts.planFraction, track: Palette.ringPlanTrack, fill: Palette.ringPlan)
            if !isOffline, let activity = counts.activity {
                if reduceMotion {
                    activityDot(activity, opacity: 1)
                } else {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.pulsePeriod) / Self.pulsePeriod
                        activityDot(activity, opacity: Self.minimumPulseOpacity + (1 - Self.minimumPulseOpacity) * (0.5 + 0.5 * cos(phase * 2 * .pi)))
                    }
                }
            }
        }
    }

    private func activityDot(_ activity: AgentRingActivity, opacity: Double) -> some View {
        Circle()
            .fill(activity.color)
            .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            .opacity(opacity)
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
