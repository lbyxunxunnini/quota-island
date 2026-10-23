import SwiftUI

struct AddProviderView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    let onAdded: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var category = "常规厂商"
    @State private var search = ""
    @State private var selected: ProviderConfig?
    @State private var comingSoon = false

    var body: some View {
        Group {
            if let selected {
                ProviderEditorView(coordinator: coordinator, initial: selected, isNew: true,
                                   onCancel: { self.selected = nil }, onSaved: onAdded)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("添加模型").font(.title2.bold())
                        Spacer()
                        Button("取消") { dismiss() }
                    }.padding(24)
                    Divider()
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(["常规厂商", "账号登录", "自定义"], id: \.self) { name in
                                Button { category = name } label: {
                                    Text(name).fontWeight(category == name ? .semibold : .regular)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .background(category == name ? Color.accentColor.opacity(0.12) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain)
                            }
                        }.frame(width: 140)
                        VStack(alignment: .leading, spacing: 18) {
                            TextField("搜索名称或网址", text: $search)
                                .textFieldStyle(.roundedBorder)
                            Text(category).font(.headline)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(providers) { provider in providerButton(provider) }
                            }
                            if category == "账号登录" {
                                Text("ChatGPT 已作为唯一内置模型自动读取本机登录。")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }.padding(24)
                }.frame(width: 900, height: 640)
            }
        }
        .alert("敬请期待", isPresented: $comingSoon) {
            Button("好", role: .cancel) {}
        } message: { Text("暂不提供新增 ChatGPT 实例。") }
    }

    private var providers: [ProviderID] {
        let sources: [ProviderID]
        switch category {
        case "账号登录": sources = [.codex]
        case "自定义": sources = [.custom]
        default: sources = ProviderID.allCases.filter { $0 != .codex && $0 != .custom }
        }
        return sources.filter { search.isEmpty || ($0.defaultName + $0.website).localizedCaseInsensitiveContains(search) }
    }

    private func providerButton(_ provider: ProviderID) -> some View {
        Button {
            if provider == .codex { comingSoon = true }
            else { selected = ProviderConfig(provider: provider) }
        } label: {
            HStack(spacing: 12) {
                ProviderMonogram(symbol: provider.compactSymbol, size: 20)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text(provider.defaultName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(provider.website).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                .opacity(provider == .codex ? 0.42 : 1)
        }.buttonStyle(.plain)
    }
}
