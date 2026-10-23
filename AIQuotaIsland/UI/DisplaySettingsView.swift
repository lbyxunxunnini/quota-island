import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("显示设置").font(.title3.bold())
            Text("使用上下按钮调整顺序；刘海最多显示 3 个来源。")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(settings.providers.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text(settings.providers[index].compactSymbol)
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 25)
                    TextField("名称", text: Binding(
                        get: { settings.providers[index].displayName },
                        set: { settings.providers[index].displayName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Toggle("面板", isOn: Binding(
                        get: { settings.providers[index].isVisible },
                        set: { settings.providers[index].isVisible = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    Toggle("刘海", isOn: Binding(
                        get: { settings.providers[index].showInCompact },
                        set: { settings.providers[index].showInCompact = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(!settings.providers[index].showInCompact && settings.compactProviders.count >= 3)
                    Button { settings.move(settings.providers[index].id, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0)
                    Button { settings.move(settings.providers[index].id, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == settings.providers.count - 1)
                }
            }
            HStack {
                Toggle("显示桌面面板", isOn: $settings.desktopVisible)
                Spacer()
                Button("完成", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 590)
    }
}
