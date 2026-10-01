import MochaClient
import MochaProtocol
import SwiftUI

struct UsageSheet: View {
    @Bindable var session: AppSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
            UsageSheetContent(usages: session.usagesByProvider, hostName: session.host?.hostName, now: context.date)
        }
    }
}

private struct UsageSheetContent: View {
    let usages: [UsageSnapshot]
    let hostName: String?
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                SheetGrabber()
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 46)
            }
            VStack(spacing: 12) {
                ForEach(usages, id: \.provider) { usage in
                    UsageCard(usage: usage, hostName: hostName, now: now)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 19.3)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Uso")
                .font(.system(size: 18, weight: .bold))
                .systemLinePitch(22, size: 18)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }
}

private struct UsageCard: View {
    let usage: UsageSnapshot
    let hostName: String?
    let now: Date

    var body: some View {
        let windows = UsagePace.summaries(of: usage, now: now)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderTile(provider: usage.provider, size: 40, cornerRadius: 11, markSize: 25)
                VStack(alignment: .leading, spacing: 3.5) {
                    Text(UsagePace.accountTitle(plan: usage.plan, account: usage.account, provider: usage.provider))
                        .systemText(.cardTitle)
                        .systemLinePitch(21, size: 16)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .systemLinePitch(16, size: 12)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(RelativeTime.text(from: usage.fetchedAt, now: now))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            if !windows.isEmpty {
                Rectangle()
                    .fill(Palette.divider)
                    .frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(windows) { window in
                        UsageWindowRow(window: window, reminder: reminder(for: window))
                    }
                }
                .padding(.top, 7.7)
                .padding(.leading, 16)
                .padding(.trailing, 17.3)
                .padding(.bottom, UsagePace.trendLine(windows) == nil ? 11 : 0)
                if let trendLine = UsagePace.trendLine(windows) {
                    Text(trendLine)
                        .font(.system(size: 14))
                        .systemLinePitch(20, size: 14)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Palette.toolCard))
    }

    private func reminder(for window: UsageWindowSummary) -> UsageResetBell? {
        guard window.kind == .fiveHour,
              let resetsAt = UsageResetReminder.fiveHourReset(of: usage),
              resetsAt > now else { return nil }
        return UsageResetBell(provider: usage.provider, resetsAt: resetsAt)
    }

    private var subtitle: String {
        let name = usage.provider == .codex ? "Codex" : "Claude Code"
        guard let hostName else { return name }
        return "\(name) · \(hostName)"
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindowSummary
    let reminder: UsageResetBell?

    var body: some View {
        HStack(spacing: 0) {
            summary
            Group {
                if let reminder {
                    reminder
                }
            }
            .frame(width: 22, alignment: .trailing)
        }
        .frame(height: 24)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            Text(window.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 40.3, alignment: .trailing)
            UsageBar(fraction: window.usedFraction, paceFraction: window.elapsedFraction)
                .frame(width: 131.7)
                .padding(.leading, 11.7)
            Text(window.percentText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 48.1, alignment: .trailing)
            Text(window.timeUntilReset ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Janela de \(window.label)")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = ["\(window.percentText) usado"]
        if let reset = window.timeUntilReset {
            parts.append("zera em \(reset)")
        }
        if let trend = window.trend {
            parts.append(trend.text)
        }
        return parts.joined(separator: ", ")
    }
}

private struct UsageResetBell: View {
    let provider: AgentProvider
    let resetsAt: Date

    var body: some View {
        let isArmed = UsageResetReminder.shared.isArmed(provider)
        Button {
            UsageResetReminder.shared.toggle(provider, resetsAt: resetsAt)
        } label: {
            Image(systemName: isArmed ? "bell.fill" : "bell")
                .font(.system(size: 13))
                .foregroundStyle(isArmed ? Palette.statusOk : Palette.textSecondary)
                .frame(width: 22, height: 24, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Avisar quando a janela de 5h zerar")
        .accessibilityValue(isArmed ? "Ligado" : "Desligado")
    }
}
