import SwiftUI

struct ProviderEditorView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    let isNew: Bool
    var onCancel: (() -> Void)?
    let onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var config: ProviderConfig
    @State private var apiKey = ""
    @State private var cookie = ""
    @State private var testSnapshot: QuotaSnapshot?
    @State private var working = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?

    init(coordinator: QuotaCoordinator, initial: ProviderConfig, isNew: Bool,
         onCancel: (() -> Void)? = nil, onSaved: @escaping (UUID) -> Void) {
        self.coordinator = coordinator
        self.isNew = isNew
        self.onCancel = onCancel
        self.onSaved = onSaved
        var config = initial
        if config.provider == .custom && config.script.isEmpty { config.script = CustomScriptGuide.starter }
        _config = State(initialValue: config)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderMonogram(symbol: config.compactSymbol, size: 22)
                    .frame(width: 42, height: 42).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(isNew ? "添加" : "编辑") \(config.displayName)").font(.title2.bold())
                    Text(config.provider.website).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsSection(title: "基本信息") {
                        if config.provider == .custom {
                            TextField("模型名称", text: $config.customName).textFieldStyle(.roundedBorder)
                        } else {
                            LabeledContent("名称") { Text(config.displayName) }
                        }
                        TextField("备注（可选），例如工作、个人", text: $config.remark).textFieldStyle(.roundedBorder)
                    }
                    SettingsSection(title: "凭据配置") {
                        if config.provider == .custom {
                            HStack {
                                SecureField("API Key（可选）", text: $apiKey)
                                SecureField("Cookie（可选）", text: $cookie)
                            }.textFieldStyle(.roundedBorder)
                        } else {
                            Text(config.provider.credentialHint).font(.callout).foregroundStyle(.secondary)
                            SecureField("粘贴 \(config.provider.credentialTitle)", text: $apiKey).textFieldStyle(.roundedBorder)
                        }
                        if !isNew {
                            Text("留空沿用已保存的凭据；输入新值后，验证成功才替换。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if config.provider == .custom {
                        CustomScriptSection(config: $config)
                    }
                    SettingsSection(title: "卡片模板") {
                        Picker("模板", selection: $config.template) {
                            ForEach(config.provider.availableTemplates) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    if let message {
                        Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if let snapshot = testSnapshot {
                        Label("查询成功", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let plan = snapshot.planName { Text(plan).font(.callout).foregroundStyle(.secondary) }
                        if let extra = snapshot.extra { Text(extra).font(.callout).foregroundStyle(.secondary) }
                        QuotaPreviewView(config: config, snapshot: snapshot)
                    } else { QuotaPreviewView(config: config) }
                }.padding(24)
            }
            Divider()
            HStack {
                Button(working ? "查询中…" : "测试查询") { perform(save: false) }.disabled(working)
                if config.provider == .custom {
                    Button("格式化") { formatScript() }.disabled(working)
                }
                Spacer()
                Button("取消") { cancel() }
                Button(working ? "验证中…" : isNew ? "验证并添加" : "验证并保存") { perform(save: true) }
                    .buttonStyle(.borderedProminent).disabled(working || config.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(20)
        }
        .frame(width: 900, height: 720)
        .onDisappear { operation?.cancel() }
    }

    private func credentials() throws -> KeychainStore.Credentials {
        var result = isNew ? KeychainStore.Credentials() : try coordinator.credentials(for: config)
        if !apiKey.isEmpty { result.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !cookie.isEmpty { result.cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines) }
        return result
    }
    private func perform(save: Bool) {
        working = true
        message = nil
        operation = Task { @MainActor in
            defer { working = false }
            do {
                let credential = try credentials()
                if save {
                    try await coordinator.save(config, credentials: credential)
                    try Task.checkCancellation()
                    apiKey = ""; cookie = ""
                    onSaved(config.id)
                } else {
                    let result = try await coordinator.validate(config, credentials: credential)
                    try Task.checkCancellation()
                    testSnapshot = result
                }
            } catch is CancellationError {}
            catch let failure as QuotaFailure { message = failure.message }
            catch { message = "查询未完成，请检查配置后重试" }
        }
    }
    private func formatScript() {
        working = true
        message = nil
        operation = Task { @MainActor in
            defer { working = false }
            do {
                let result = try await CustomScriptEngine.format(config.script, timeout: config.timeout)
                try Task.checkCancellation()
                config.script = result
            } catch let failure as QuotaFailure { message = failure.message }
            catch { message = "格式化未完成，请检查脚本" }
        }
    }
    private func cancel() {
        operation?.cancel()
        if let onCancel { onCancel() } else { dismiss() }
    }
}
