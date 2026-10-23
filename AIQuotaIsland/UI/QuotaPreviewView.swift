import SwiftUI

struct QuotaPreviewView: View {
    let config: ProviderConfig
    var snapshot: QuotaSnapshot? = nil
    @State private var previewNow = Date()
    private var sample: QuotaSnapshot { snapshot ?? QuotaSamples.snapshot(for: config, now: previewNow) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("卡片预览").font(.headline)
                Spacer()
                Text(snapshot == nil ? "示例数据" : "本次查询结果").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    Text("竖排").font(.caption).foregroundStyle(.white.opacity(0.7))
                    QuotaCardView(config: config, state: ProviderState(snapshot: sample),
                                  now: sample.fetchedAt, fullWidth: false)
                        .frame(width: 200)
                }
                VStack(spacing: 8) {
                    Text("横排").font(.caption).foregroundStyle(.white.opacity(0.7))
                    QuotaCardView(config: config, state: ProviderState(snapshot: sample),
                                  now: sample.fetchedAt, fullWidth: true)
                        .frame(maxWidth: .infinity)
                }.frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(QuotaPalette.backdrop, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
