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
                let fraction = state.snapshot?.remainingFraction
                ZStack {
                    Circle().stroke(.white.opacity(0.26), lineWidth: 3)
                    if failed {
                        Circle().stroke(QuotaPalette.red, lineWidth: 3)
                    } else if let fraction {
                        Circle().trim(from: 0, to: max(0.001, fraction))
                            .stroke(QuotaPalette.remainingGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text(config.compactSymbol)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if let credits = state.snapshot?.resetCredits, credits.availableCount > 0 {
                        Text("↻\(credits.availableCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .background(QuotaPalette.backdrop, in: Capsule())
                            .offset(x: 10, y: -6)
                    }
                }
                .frame(width: 29, height: 29)
                .frame(width: 37, height: 36)
                .accessibilityLabel("\(config.displayName)，\(failed ? "额度失效" : fraction.map { "剩余 \(QuotaPercentage.text($0))" } ?? "等待查询")")
            }
        }
        .padding(.horizontal, 3)
        .background(QuotaPalette.backdrop.opacity(0.76), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onHover { inside in inside ? onOpen() : onLeave() }
        .onTapGesture(perform: onOpen)
    }
}
