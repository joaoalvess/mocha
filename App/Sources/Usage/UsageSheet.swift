import MochaClient
import MochaProtocol
import SwiftUI

struct UsageSheet: View {
    @Bindable var session: AppSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
            UsageSheetContent(usage: session.usage, hostName: session.host?.hostName, now: context.date)
        }
    }
}

private struct UsageSheetContent: View {
    let usage: UsageSnapshot?
    let hostName: String?
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                SheetGrabber()
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 46)
            }
            if let usage {
                UsageCard(usage: usage, hostName: hostName, now: now)
                    .padding(.horizontal, 20)
                    .padding(.top, 19.3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Uso")
                .systemText(.sheetTitle)
                .systemLinePitch(22, size: 17)
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
            HStack(spacing: 13.3) {
                ClaudeTile(size: 40, cornerRadius: 11, background: Palette.claudeTile, markSize: 25)
                VStack(alignment: .leading, spacing: 3.5) {
                    Text(UsagePace.accountTitle(plan: usage.plan, account: usage.account))
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
                        UsageWindowRow(window: window)
                    }
                }
                .padding(.top, 8.7)
                .padding(.leading, 16)
                .padding(.trailing, 17.3)
                .padding(.bottom, UsagePace.trendLine(windows) == nil ? 10 : 0)
                if let trendLine = UsagePace.trendLine(windows) {
                    Text(trendLine)
                        .font(.system(size: 14))
                        .systemLinePitch(20, size: 14)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 9)
                        .padding(.bottom, 10)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Palette.toolCard))
    }

    private var subtitle: String {
        guard let hostName else { return "Claude Code" }
        return "Claude Code · \(hostName)"
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindowSummary

    var body: some View {
        HStack(spacing: 0) {
            Text(window.label)
                .font(Typography.usageLabel)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 38.7, alignment: .trailing)
            UsageBar(fraction: window.usedFraction, paceFraction: window.elapsedFraction)
                .frame(width: 153.7)
                .padding(.leading, 13.3)
            Text(window.percentText)
                .font(Typography.usageValue)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 47.3, alignment: .trailing)
            Text(window.timeUntilReset ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 24)
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
