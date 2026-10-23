import SwiftUI

struct QuotaCardView: View {
    let config: ProviderConfig
    let state: ProviderState
    let now: Date
    let fullWidth: Bool
    var revealID: UUID? = nil
    var onClick: (() -> Void)? = nil
    @State private var reveal = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: QuotaSnapshot? { state.snapshot }
    private var failure: QuotaFailure? { state.effectiveFailure(at: now) }
    private var hardFailure: Bool { failure.map { $0.kind != .temporary } ?? false }
    private var balanceMode: Bool {
        if let snapshot { return snapshot.balance != nil }
        return config.provider.isBalance || config.currency != nil
    }
    private var isLarge: Bool {
        if balanceMode || snapshot?.totalQuota != nil { return false }
        if config.provider == .codex { return true }
        if config.template == .single { return false }
        return snapshot?.isLargeCard ?? (config.template != .single)
    }
    private var singleQuota: TotalQuota? {
        if let quota = snapshot?.totalQuota { return quota }
        guard !isLarge, let window = snapshot?.ringWindow,
              let remaining = window.remainingAmount else { return nil }
        return TotalQuota(remaining: remaining, total: window.totalAmount, unit: window.unit ?? "",
                          expiresAt: nil, resetsAt: window.resetsAt)
    }

    var body: some View {
        Group {
            if let onClick {
                Button(action: onClick) { cardContent }
                    .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .help(config.provider == .codex ? "自动读取本机 Codex 登录" : "点击编辑 \(config.displayName) 凭据")
        .task(id: revealID) { await animateEntry() }
    }

    private var cardContent: some View {
        Group {
            if fullWidth {
                HStack(spacing: 16) {
                    gauge
                    VStack(alignment: .leading, spacing: 7) {
                        name
                        details
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(11)
                .frame(minHeight: isLarge ? 175 : 131)
            } else {
                VStack(spacing: 0) {
                    gauge.padding(.top, 5)
                    name.padding(.top, 8)
                    Spacer(minLength: 6)
                    details
                }
                .padding(11)
                .frame(height: 251)
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .background(QuotaPalette.card.opacity(0.76), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.12)))
        .overlay(alignment: .topTrailing) {
            if config.provider != .codex && !isLarge {
                Image(systemName: "key.fill").font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6)).padding(12)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 17))
    }

    private var name: some View {
        Text(config.title).font(.system(size: 18, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.75)
    }
    @ViewBuilder private var gauge: some View {
        if balanceMode && !hardFailure {
            WaterTankView(amount: snapshot?.balance?.remaining,
                          symbol: QuotaFormat.currencySymbol(snapshot?.balance?.currency ?? config.currency),
                          reveal: reveal, pulse: snapshot?.fetchedAt)
        } else {
            RingView(fraction: snapshot?.remainingFraction, accent: QuotaPalette.ringAccent(for: config.provider),
                     failed: hardFailure, reveal: reveal)
        }
    }

    @ViewBuilder private var details: some View {
        if let balance = snapshot?.balance {
            Text("余额 \(QuotaFormat.money(balance.remaining, currency: balance.currency))")
                .font(.system(size: 18, weight: .medium))
            if !fullWidth { Spacer(minLength: 6) }
        } else if let total = singleQuota {
            if fullWidth {
                Text("剩余 \(QuotaFormat.compact(total.remaining))\(total.total.map { " / \(QuotaFormat.compact($0))" } ?? "") \(total.unit)")
                    .font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text("剩余 \(QuotaFormat.compact(total.remaining))\(total.total == nil ? " \(total.unit)" : "")")
                    .font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.8)
            }
            if !fullWidth, let amount = total.total {
                if !fullWidth { Spacer(minLength: 6) }
                Text("总量 \(QuotaFormat.compact(amount)) \(total.unit)")
                    .font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.8)
            }
            if !fullWidth { Spacer(minLength: 6) }
        } else if let windows = snapshot?.windows, !windows.isEmpty, isLarge {
            periodRows(windows)
            if !fullWidth { Spacer(minLength: 6) }
        } else if snapshot == nil && failure == nil {
            Text(state.isRefreshing ? "正在查询…" : "等待查询")
                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
        }
        if let credits = snapshot?.resetCredits {
            Label("可用重置 \(credits.availableCount) 次", systemImage: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.white.opacity(0.11), in: Capsule())
            if !fullWidth { Spacer(minLength: 5) }
        }
        statusLine
    }

    private func periodRows(_ windows: [QuotaWindow]) -> some View {
        VStack(spacing: 6) {
            ForEach(windows) { window in
                HStack(spacing: 6) {
                    Text(window.title).frame(width: 48, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(QuotaPalette.track.opacity(0.6))
                            Capsule().fill(QuotaPalette.barAccent(for: config.provider))
                                .frame(width: geometry.size.width * window.clampedFraction)
                        }
                    }.frame(height: 8)
                    Text(window.remainingAmount.map { QuotaFormat.compact($0) + (window.unit.map { " \($0)" } ?? "") } ?? QuotaPercentage.text(window.clampedFraction))
                        .frame(minWidth: 42, alignment: .trailing)
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        Group {
            if let failure {
                VStack(spacing: 2) {
                    Text(failure.message).foregroundStyle(failure.kind == .temporary ? QuotaPalette.peach : QuotaPalette.red)
                    if failure.kind == .temporary, let fetched = snapshot?.fetchedAt {
                        Text("旧数据：\(QuotaFormat.elapsed(fetched, now: now))")
                    }
                }
            } else if state.isRefreshing {
                Text("更新中…")
            } else if let expiry = singleQuota?.expiresAt {
                Label("\(QuotaFormat.date(expiry)) 到期", systemImage: "calendar")
            } else if let reset = singleQuota?.resetsAt {
                Label("\(QuotaFormat.date(reset)) 重置", systemImage: "calendar")
            } else if let balance = snapshot?.balance {
                Text(balance.remaining <= 0 ? "余额不足" : balance.remaining <= 10 ? "余额偏低" :
                     balance.remaining > 100 ? "余额充足" : "余额正常")
                    .foregroundStyle(balance.remaining <= 0 ? QuotaPalette.red : .white.opacity(0.72))
            } else if let reset = (isLarge ? snapshot?.resetWindow : snapshot?.ringWindow)?.resetsAt {
                Text(isLarge ? "下次重置 \(QuotaFormat.countdown(reset, now: now))" : "\(QuotaFormat.date(reset)) 重置")
            } else if let extra = snapshot?.extra, !extra.isEmpty {
                Text(extra)
            } else if snapshot != nil {
                Text("数据已更新")
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(2).minimumScaleFactor(0.8)
        .padding(.top, 2)
    }

    private func animateEntry() async {
        guard revealID != nil, !reduceMotion else { reveal = 1; return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { reveal = 0 }
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.7)) { reveal = 1 }
    }
}
