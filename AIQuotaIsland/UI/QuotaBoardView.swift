import SwiftUI

enum QuotaPalette {
    static let backdrop = Color(red: 0.20, green: 0.29, blue: 0.47)
    static let card = Color(red: 0.30, green: 0.39, blue: 0.58)
    static let track = Color(red: 0.50, green: 0.58, blue: 0.73)
    static let remainingGreen = Color(red: 35.0 / 255, green: 210.0 / 255, blue: 82.0 / 255)
    static let ocean = Color(red: 0.20, green: 0.57, blue: 0.74)
    static let orange = Color(red: 1.00, green: 0.66, blue: 0.30)
    static let peach = Color(red: 1.00, green: 0.82, blue: 0.68)
    static let red = Color(red: 1.00, green: 0.40, blue: 0.43)

    static func ringAccent(for id: ProviderID) -> Color {
        switch id {
        case .opencodeGo: remainingGreen
        case .codex: remainingGreen
        case .spark: orange
        }
    }

    static func barAccent(for id: ProviderID) -> Color {
        switch id {
        case .opencodeGo: ocean
        case .codex: ocean
        case .spark: orange
        }
    }
}

struct RingView: View {
    let fraction: Double?
    let accent: Color
    let failed: Bool
    var diameter: CGFloat = 112

    var body: some View {
        ZStack {
            Circle().stroke(QuotaPalette.track.opacity(0.54), lineWidth: diameter * 0.095)
            if failed {
                Circle().stroke(QuotaPalette.red, lineWidth: diameter * 0.095)
            } else if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(accent, style: StrokeStyle(lineWidth: diameter * 0.095, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if failed {
                Text("∞")
                    .font(.system(size: diameter >= 85 ? 34 : 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else if let fraction {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(QuotaPercentage.whole(fraction) ?? 0)")
                        .font(.system(size: diameter >= 85 ? 34 : 26, weight: .bold, design: .rounded))
                    if QuotaPercentage.whole(fraction) != 100 {
                        Text("%")
                            .font(.system(size: diameter >= 85 ? 19 : 15, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
            } else {
                Text("—")
                    .font(.system(size: diameter >= 85 ? 34 : 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(failed ? "额度失效" : fraction.map { "剩余\(QuotaPercentage.text($0))" } ?? "等待查询")
    }
}

struct QuotaCardView: View {
    let config: ProviderConfig
    let state: ProviderState
    let now: Date
    let fullWidth: Bool
    let onSparkClick: () -> Void
    let onGoClick: () -> Void

    private var snapshot: QuotaSnapshot? { state.snapshot }
    private var failure: QuotaFailure? { state.effectiveFailure(at: now) }
    private var hardFailure: Bool { failure.map { $0.kind != .temporary } ?? false }
    private var isLarge: Bool { snapshot?.isLargeCard ?? (config.id != .spark) }

    var body: some View {
        Group {
            if isLarge {
                if fullWidth { horizontalLargeCard } else { verticalLargeCard }
            } else {
                if fullWidth { horizontalSmallCard } else { verticalSmallCard }
            }
        }
        .frame(maxWidth: .infinity)
        .background(QuotaPalette.card.opacity(0.76), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.12)))
        .contentShape(RoundedRectangle(cornerRadius: 17))
        .onTapGesture {
            if config.id == .spark { onSparkClick() }
            if config.id == .opencodeGo { onGoClick() }
        }
        .help(config.id == .spark ? "点击更换讯飞 Cookie" :
              config.id == .opencodeGo ? "点击更换 OpenCode Go Key" : config.displayName)
    }

    private var verticalLargeCard: some View {
        VStack(spacing: 0) {
            verticalHeader
            if let windows = snapshot?.windows, !windows.isEmpty {
                Spacer(minLength: 4)
                periodRows(windows)
            }
            if let credits = snapshot?.resetCredits {
                Spacer(minLength: 4)
                resetBadge(credits)
            }
            Spacer(minLength: 4)
            statusLine
        }
        .foregroundStyle(.white)
        .padding(11)
        .frame(height: 251)
    }

    private var horizontalLargeCard: some View {
        HStack(spacing: 16) {
            cardRing
            largeDetails(horizontal: true)
        }
        .foregroundStyle(.white)
        .padding(11)
        .frame(minHeight: 175)
    }

    private func largeDetails(horizontal: Bool) -> some View {
        VStack(alignment: horizontal ? .leading : .center, spacing: 6) {
            Text(config.displayName).font(.system(size: 18, weight: .semibold)).lineLimit(1)
            if let windows = snapshot?.windows, !windows.isEmpty {
                periodRows(windows)
                .padding(.top, windows.count > 1 ? 7 : 0)
            }
            if let credits = snapshot?.resetCredits {
                resetBadge(credits)
            }
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: horizontal ? .leading : .center)
    }

    private var horizontalSmallCard: some View {
        HStack(spacing: 16) {
            cardRing
            horizontalSmallDetails
        }
        .foregroundStyle(.white)
        .padding(11)
        .frame(minHeight: 111)
        .overlay(alignment: .topTrailing) {
            if config.id == .spark {
                Image(systemName: "key.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(12)
            }
        }
    }

    private var verticalSmallCard: some View {
        VStack(spacing: 0) {
            verticalHeader
            if let total = snapshot?.totalQuota {
                Spacer(minLength: 4)
                Text("剩余 \(formatTokens(total.remaining))")
                    .font(.system(size: 16))
                Spacer(minLength: 4)
                Text("总量 \(formatTokens(total.total)) \(total.unit)")
                    .font(.system(size: 16))
                if let expiry = total.expiresAt {
                    Spacer(minLength: 4)
                    Label(expiry <= now ? "已到期" : "\(formatDate(expiry)) 到期", systemImage: "calendar")
                        .font(.system(size: 16))
                        .lineLimit(2)
                }
            } else if let window = snapshot?.ringWindow {
                Spacer(minLength: 4)
                Text("剩余 \(QuotaPercentage.text(window.clampedFraction))")
                    .font(.system(size: 16))
            } else {
                Spacer(minLength: 4)
                Text(failure?.kind == .authentication && config.id == .spark ? "设置 Cookie 后查询" : "等待查询")
                    .font(.system(size: 16))
            }
            if config.id != .spark || failure != nil || snapshot == nil {
                Spacer(minLength: 4)
                statusLine
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(11)
        .frame(height: 251)
        .overlay(alignment: .topTrailing) {
            if config.id == .spark {
                Image(systemName: "key.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(12)
            }
        }
    }

    private var cardRing: some View {
        RingView(fraction: snapshot?.remainingFraction, accent: QuotaPalette.ringAccent(for: config.id),
                 failed: hardFailure, diameter: 90)
    }

    private var verticalHeader: some View {
        VStack(spacing: 8) {
            cardRing.padding(.top, 5)
            Text(config.displayName)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private func periodRows(_ windows: [QuotaWindow]) -> some View {
        VStack(spacing: 6) {
            ForEach(windows) { window in
                HStack(spacing: 6) {
                    Text(window.title).frame(width: 48, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(QuotaPalette.track.opacity(0.6))
                            Capsule().fill(QuotaPalette.barAccent(for: config.id))
                                .frame(width: geometry.size.width * window.clampedFraction)
                        }
                    }
                    .frame(height: 8)
                    Text(QuotaPercentage.text(window.clampedFraction))
                        .frame(width: 42, alignment: .trailing)
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
            }
        }
    }

    private func resetBadge(_ credits: ResetCredits) -> some View {
        Label("可用重置 \(credits.availableCount) 次", systemImage: "arrow.clockwise")
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white.opacity(0.11), in: Capsule())
    }

    private var horizontalSmallDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(config.displayName)
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.85)
            if let total = snapshot?.totalQuota {
                Text("剩余 \(formatTokens(total.remaining)) / \(formatTokens(total.total)) \(total.unit)")
                    .font(.system(size: 16))
                    .lineLimit(1).minimumScaleFactor(0.85)
                if let expiry = total.expiresAt {
                    Label(expiry <= now ? "已到期" : "\(formatDate(expiry)) 到期", systemImage: "calendar")
                        .font(.system(size: 16))
                        .lineLimit(1)
                }
            } else if let window = snapshot?.ringWindow {
                Text("剩余 \(QuotaPercentage.text(window.clampedFraction))")
                    .font(.system(size: 16))
            } else {
                Text(failure?.kind == .authentication && config.id == .spark ? "设置 Cookie 后查询" : "等待查询")
                    .font(.system(size: 16))
            }
            if config.id != .spark || failure != nil || snapshot == nil {
                statusLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: some View {
        Group {
            if let failure {
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.message)
                        .foregroundStyle(failure.kind == .temporary ? QuotaPalette.peach : QuotaPalette.red)
                    if failure.kind == .temporary, let fetchedAt = snapshot?.fetchedAt {
                        Text("旧数据：\(elapsedTime(since: fetchedAt))")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            } else if state.isRefreshing {
                Text("更新中…")
            } else if let reset = snapshot?.ringWindow?.resetsAt {
                Text("下次重置 \(relativeTime(reset))")
            } else {
                Text(snapshot == nil ? "等待查询" : "数据已更新")
            }
        }
        .font(.system(size: 16, weight: .medium))
        .lineLimit(2)
        .foregroundStyle(.white.opacity(0.72))
        .padding(.top, 2)
    }

    private func relativeTime(_ date: Date) -> String {
        guard date > now else { return "即将重置" }
        let interval = Int(date.timeIntervalSince(now))
        if interval >= 86_400 { return "\(interval / 86_400)天 \((interval % 86_400) / 3_600)小时" }
        if interval >= 3_600 { return "\(interval / 3_600)小时 \((interval % 3_600) / 60)分钟" }
        return "\(max(1, interval / 60))分钟"
    }

    private func elapsedTime(since date: Date) -> String {
        let interval = max(0, Int(now.timeIntervalSince(date)))
        if interval < 60 { return "刚刚" }
        if interval < 3_600 { return "\(interval / 60)分钟前" }
        if interval < 86_400 { return "\(interval / 3_600)小时前" }
        return "\(interval / 86_400)天前"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func formatTokens(_ value: Double) -> String {
        if value >= 100_000_000 { return String(format: "%.2f亿", value / 100_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

struct QuotaBoardView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    @ObservedObject var settings: AppSettings
    let title: String
    let onSparkClick: () -> Void
    let onGoClick: () -> Void
    let onSettingsClick: () -> Void

    private var rows: [[ProviderConfig]] {
        let items = settings.visibleProviders
        return LayoutPlanner.boardRows(items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 19, weight: .bold))
                Spacer()
                Button(action: onSettingsClick) { Image(systemName: "gearshape").font(.system(size: 18)) }
                    .buttonStyle(.plain).help("显示设置")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 17).padding(.top, 13).padding(.bottom, 9)

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        HStack(alignment: .top, spacing: 9) {
                            ForEach(row) { config in
                                QuotaCardView(config: config,
                                              state: coordinator.states[config.id] ?? ProviderState(),
                                              now: coordinator.now,
                                              fullWidth: row.count == 1,
                                              onSparkClick: onSparkClick,
                                              onGoClick: onGoClick)
                            }
                        }
                    }
                    if rows.isEmpty {
                        Text("请在设置中选择要显示的额度")
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(30)
                    }
                }
                .padding(.horizontal, 12)
            }
            Divider().overlay(.white.opacity(0.3)).padding(.horizontal, 15)
            HStack {
                Text("最近成功更新：\(latestUpdate)")
                    .font(.system(size: 17)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button {
                    Task { await coordinator.refreshAll(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18))
                        .rotationEffect(.degrees(coordinator.isRefreshing ? 45 : 0))
                }
                .buttonStyle(.plain).help("立即刷新")
                .disabled(coordinator.isRefreshing)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 17).padding(.vertical, 10)
        }
        .background(QuotaPalette.backdrop, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.15)))
    }

    private var latestUpdate: String {
        let dates = coordinator.states.values.compactMap { $0.snapshot?.fetchedAt }
        guard let latest = dates.max() else { return "尚未获取" }
        let seconds = max(0, Int(coordinator.now.timeIntervalSince(latest)))
        if seconds < 60 { return "刚刚" }
        return "\(seconds / 60) 分钟前"
    }
}
