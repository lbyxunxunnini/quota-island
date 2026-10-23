import SwiftUI

struct CredentialEditorView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    let provider: ProviderID
    let onClose: () -> Void

    @State private var secret = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "key.horizontal.fill").foregroundStyle(QuotaPalette.peach)
                Text(provider == .spark ? "更换讯飞 Cookie" : "更换 OpenCode Go Key").font(.title3.bold())
            }
            Text(provider == .spark
                 ? "粘贴新的 Cookie 后会先查询验证，成功才替换已保存的凭据。"
                 : "粘贴新的 OpenCode Go Key 后会先查询验证，成功才替换已保存的凭据。")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField(provider == .spark ? "粘贴完整 Cookie" : "粘贴 OpenCode Go Key", text: $secret)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button(isSaving ? "验证中…" : "验证并保存") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func submit() {
        let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                if provider == .spark {
                    try await coordinator.replaceSparkCookie(value)
                } else {
                    try await coordinator.replaceOpenCodeGoKey(value)
                }
                secret = ""
                onClose()
            } catch let failure as QuotaFailure {
                errorMessage = failure.message
            } catch {
                errorMessage = "验证失败，请检查凭据与网络后重试"
            }
            isSaving = false
        }
    }
}
