import SwiftUI
import UniformTypeIdentifiers

struct DisplaySettingsView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void
    @State private var selectedID: UUID?
    @State private var adding = false
    @State private var editing: ProviderConfig?
    @State private var deleting: ProviderConfig?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                if let config = selected {
                    detail(config).padding(20)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        }
        .frame(minWidth: 1000, minHeight: 680)
        .onAppear { if selectedID == nil { selectedID = settings.providers.first?.id } }
        .sheet(isPresented: $adding) {
            AddProviderView(coordinator: coordinator) { id in adding = false; selectedID = id }
        }
        .sheet(item: $editing) { config in
            ProviderEditorView(coordinator: coordinator, initial: config, isNew: false) { _ in editing = nil }
        }
        .alert("删除模型？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                guard let config = deleting else { return }
                do {
                    try coordinator.remove(config.id)
                    selectedID = settings.providers.first?.id
                } catch let failure as QuotaFailure { errorMessage = failure.message }
                catch { errorMessage = "删除失败，请重试" }
                deleting = nil
            }
        } message: {
            Text("将移除「\(deleting?.title ?? "")」及该实例保存在本 App 的凭据。")
        }
        .alert("操作未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var selected: ProviderConfig? {
        selectedID.flatMap(settings.config) ?? settings.providers.first
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("模型").font(.title2.bold())
                Spacer()
                Text("刘海 \(settings.compactProviders.count) / 4").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("拖动调整顺序").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("面板").frame(width: 30)
                Text("刘海").frame(width: 30)
            }.font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(settings.providers) { config in providerRow(config) }
                }
            }
            Button { adding = true } label: {
                Label("添加模型", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.borderedProminent)
            Divider()
            Toggle("显示桌面面板", isOn: $settings.desktopVisible).toggleStyle(.switch)
            HStack {
                Text("自动刷新")
                Spacer()
                Picker("自动刷新", selection: $settings.refreshMinutes) {
                    ForEach(AppSettings.refreshChoices, id: \.self) { Text("\($0) 分钟").tag($0) }
                }.labelsHidden().frame(width: 105)
            }
            Button("完成", action: onClose).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(18).frame(width: 270)
    }

    private func providerRow(_ config: ProviderConfig) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(.tertiary)
            ProviderIcon(provider: config.provider, symbol: config.iconSymbol, imageData: config.iconImage, size: 28)
                .frame(height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(config.displayName).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.8)
                if !config.remark.isEmpty { Text(config.remark).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle("显示\(config.title)面板", isOn: field(config.id, \.isVisible))
                .labelsHidden().toggleStyle(.checkbox).frame(width: 30)
            Toggle("显示\(config.title)刘海", isOn: field(config.id, \.showInCompact))
                .labelsHidden().toggleStyle(.checkbox).frame(width: 30)
                .disabled(!config.showInCompact && settings.compactProviders.count >= 4)
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .background(selected?.id == config.id ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle()).onTapGesture { selectedID = config.id }
        .onDrag { NSItemProvider(object: config.id.uuidString as NSString) }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: NSString.self) { string, _ in
                guard let string = string as? String, let id = UUID(uuidString: string) else { return }
                Task { @MainActor in settings.move(id, to: config.id) }
            }
            return true
        }
    }

    private func field<Value>(_ id: UUID, _ path: WritableKeyPath<ProviderConfig, Value>) -> Binding<Value> {
        let fallback = settings.config(id) ?? ProviderConfig(provider: .codex)
        return Binding(get: { (settings.config(id) ?? fallback)[keyPath: path] }, set: { value in
            guard var config = settings.config(id) else { return }
            config[keyPath: path] = value
            settings.update(config)
        })
    }

    private func detail(_ config: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(config.displayName).font(.title2.bold())
                    Text(config.provider.website).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if config.provider != .codex {
                    Button(role: .destructive) { deleting = config } label: { Image(systemName: "trash") }
                        .help("删除该模型")
                }
            }
            SettingsSection(title: "基本信息") {
                HStack(spacing: 30) {
                    LabeledContent("名称") { Text(config.displayName) }
                    Spacer()
                    LabeledContent("刘海标识") { ProviderMonogram(symbol: config.compactSymbol) }
                }
                TextField("备注，例如工作、个人", text: field(config.id, \.remark)).textFieldStyle(.roundedBorder)
            }
            SettingsSection(title: "额度查询") {
                HStack(spacing: 14) {
                    Text(config.provider.credentialHint).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if config.provider == .codex {
                        Button("立即查询") { Task { await coordinator.refresh(config.id, force: true) } }
                    } else {
                        Button(config.provider == .custom ? "编辑查询配置" : "更换 \(config.provider.credentialTitle)") { editing = config }
                    }
                }
                if let failure = coordinator.states[config.id]?.failure {
                    Text(failure.message).font(.callout).foregroundStyle(.red)
                }
            }
            HStack {
                Text("卡片模板").font(.headline)
                Picker("模板", selection: field(config.id, \.template)) {
                    ForEach(config.provider.availableTemplates) {
                        Text($0.title).tag($0)
                    }
                }.pickerStyle(.segmented).labelsHidden()
            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            QuotaPreviewView(config: config)
        }
    }
}
