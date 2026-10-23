import SwiftUI

struct QuotaBoardView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    @ObservedObject var settings: AppSettings
    let title: String
    var isExpanded = false
    let onEdit: (UUID) -> Void
    let onSettingsClick: () -> Void

    private var rows: [[ProviderConfig]] { LayoutPlanner.boardRows(settings.visibleProviders) }
    private var isSingle: Bool { settings.visibleProviders.count == 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 19, weight: .bold)).lineLimit(1)
                Spacer()
                Button(action: onSettingsClick) {
                    Image(systemName: "gearshape").font(.system(size: 18))
                }.buttonStyle(.plain).help("打开设置")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 17).padding(.top, 13).padding(.bottom, 9)

            ScrollView {
                if rows.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.stack").font(.largeTitle)
                        Text("所有模型已隐藏")
                        Button("打开设置", action: onSettingsClick)
                    }.foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity).padding(30)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(rows.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: 9) {
                                ForEach(rows[index]) { config in
                                    QuotaCardView(config: config, state: coordinator.states[config.id] ?? ProviderState(),
                                                  now: coordinator.now, fullWidth: !isSingle && rows[index].count == 1,
                                                  revealID: isExpanded ? coordinator.expansionID : nil,
                                                  onClick: config.provider == .codex ? nil : { onEdit(config.id) })
                                }
                            }
                        }
                    }.padding(.horizontal, 12)
                }
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(.white.opacity(0.25)).frame(height: 1).padding(.horizontal, 15).padding(.top, 9)
            HStack {
                Text("\(isSingle ? "更新" : "最近成功更新")：\(updatedText)")
                    .font(.system(size: 15, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 5)
                Button { Task { await coordinator.refreshAll(force: true) } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 18))
                }.buttonStyle(.plain).disabled(coordinator.isRefreshing).help("刷新所有额度")
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 17).padding(.vertical, 10)
        }
        .background(QuotaPalette.backdrop, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.22)))
    }

    private var updatedText: String {
        let dates = settings.visibleProviders.compactMap { coordinator.states[$0.id]?.snapshot?.fetchedAt }
        guard let date = dates.max() else { return "尚未成功" }
        return QuotaFormat.elapsed(date, now: coordinator.now)
    }
}
