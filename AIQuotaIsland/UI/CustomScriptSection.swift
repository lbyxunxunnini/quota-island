import AppKit
import SwiftUI

struct CustomScriptSection: View {
    @Binding var config: ProviderConfig
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "请求配置") {
                TextField("基础地址（可选），例如 https://example.com", text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("超时时间")
                    Spacer()
                    Stepper("\(Int(config.timeout)) 秒", value: $config.timeout, in: 1...60, step: 1)
                        .frame(width: 150)
                }
            }
            SettingsSection(title: "查询脚本") {
                HStack {
                    Button(expanded ? "收起说明" : "查看说明") { expanded.toggle() }
                    Button(copied ? "已复制" : "复制给AI") {
                        NSPasteboard.general.clearContents()
                        if NSPasteboard.general.setString(CustomScriptGuide.text, forType: .string) {
                            copied = true
                        }
                    }
                    Spacer()
                }
                if expanded {
                    Text(CustomScriptGuide.text).font(.system(size: 12))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
                TextEditor(text: $config.script)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8).frame(minHeight: 260)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .accessibilityLabel("request 与 extractor 查询脚本")
            }
        }
    }
}
