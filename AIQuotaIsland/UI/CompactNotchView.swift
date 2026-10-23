import SwiftUI

struct CompactNotchView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    @ObservedObject var settings: AppSettings
    let providers: [ProviderConfig]
    let onOpen: () -> Void
    let onLeave: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(providers) { config in
                let state = coordinator.states[config.id] ?? ProviderState()
                let failed = state.effectiveFailure(at: coordinator.now).map { $0.kind != .temporary } ?? false
                let balance = state.snapshot?.balance
                let balanceMode = balance != nil || (state.snapshot == nil && (config.provider.isBalance || config.currency != nil))
                ZStack {
                    if balanceMode && !failed {
                        WaterTankView(amount: balance?.remaining, symbol: config.compactSymbol,
                                      diameter: 29, pulse: state.snapshot?.fetchedAt)
                    } else {
                        RingView(fraction: state.snapshot?.remainingFraction, accent: QuotaPalette.remainingGreen,
                                 failed: failed, diameter: 29, symbol: config.compactSymbol)
                    }
                    if let credits = state.snapshot?.resetCredits, credits.availableCount > 0 {
                        Text("↻\(credits.availableCount)")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .background(QuotaPalette.backdrop, in: Capsule())
                            .offset(x: 10, y: -8)
                    }
                }
                .frame(width: 37, height: 36)
                .accessibilityLabel("\(config.title)，\(failed ? "额度失效" : balance.map { QuotaFormat.money($0.remaining, currency: $0.currency) } ?? state.snapshot?.remainingFraction.map { QuotaPercentage.text($0) } ?? "等待查询")")
            }
        }
        .padding(.horizontal, 3)
        .background(QuotaPalette.backdrop.opacity(0.76), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onHover { inside in inside ? onOpen() : onLeave() }
        .onTapGesture(perform: onOpen)
    }
}
