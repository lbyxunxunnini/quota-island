import Foundation

enum CustomScriptEngine {
    static func fetch(_ config: ProviderConfig, credentials: KeychainStore.Credentials) async throws -> QuotaSnapshot {
        let request = try await makeRequest(config, credentials: credentials)
        let data = try await QuotaHTTPClient.send(request, label: "自定义")
        guard let response = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw QuotaFailure.unavailable("接口没有返回有效 JSON")
        }
        let reply = try await ScriptProcessRunner.run(
            ["action": "extract", "script": config.script, "response": response], timeout: config.timeout)
        try Task.checkCancellation()
        guard let value = reply["result"] as? [String: Any] else {
            throw QuotaFailure.unavailable("提取器未返回有效对象")
        }
        do { return try CustomQuotaParser.parse(value) }
        catch let failure as QuotaFailure {
            var message = failure.message
            for secret in [credentials.apiKey, credentials.cookie] where !secret.isEmpty {
                message = message.replacingOccurrences(of: secret, with: "••••")
            }
            throw QuotaFailure(kind: failure.kind, message: String(message.prefix(160)))
        }
    }

    static func format(_ script: String, timeout: Double) async throws -> String {
        let result = try await ScriptProcessRunner.run(["action": "format", "script": script], timeout: timeout)
        guard let value = result["text"] as? String else { throw QuotaFailure.unavailable("格式化未返回脚本") }
        return value
    }

    static func makeRequest(_ config: ProviderConfig, credentials: KeychainStore.Credentials) async throws -> URLRequest {
        guard !config.script.isEmpty, config.script.utf8.count <= 131_072 else {
            throw QuotaFailure.unavailable("请填写脚本，长度不得超过128KB")
        }
        for secret in [credentials.apiKey, credentials.cookie] where secret.count >= 6 {
            if config.script.contains(secret) {
                throw QuotaFailure.unavailable("请从脚本移除真实凭据，改用 {{apiKey}} 或 {{cookie}}")
            }
        }
        for value in [credentials.apiKey, credentials.cookie] where !value.isEmpty {
            if value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                throw QuotaFailure.authentication("凭据包含无效换行或控制字符")
            }
        }
        let reply = try await ScriptProcessRunner.run(["action": "request", "script": config.script], timeout: config.timeout)
        try Task.checkCancellation()
        guard let template = reply["result"] as? [String: Any], let address = template["url"] as? String else {
            throw QuotaFailure.unavailable("request.url 必须是字符串")
        }
        try checkSecrets(template)
        if let components = URLComponents(string: address) {
            for item in components.queryItems ?? [] where sensitive(item.name) {
                try checkSecretString(item.value ?? "")
            }
        }
        let replacements = [
            "{{apiKey}}": credentials.apiKey, "{{cookie}}": credentials.cookie,
            "{{baseUrl}}": config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        ]
        func resolve(_ text: String) -> String {
            replacements.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
        }
        guard let url = URL(string: resolve(address)), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else {
            throw QuotaFailure.unavailable("请填写有效HTTP或HTTPS请求地址，地址中不能包含用户名或密码")
        }
        let method = (template["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(method) else {
            throw QuotaFailure.unavailable("request.method 不是支持的HTTP方法")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = min(60, max(1, config.timeout))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let headers = template["headers"] as? [String: Any] {
            for (name, raw) in headers {
                guard let templateValue = raw as? String,
                      !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw QuotaFailure.unavailable("请求头必须是有效字符串")
                }
                let value = resolve(templateValue)
                guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw QuotaFailure.unavailable("请求头包含控制字符")
                }
                if value.trimmingCharacters(in: .whitespaces).isEmpty || value == "Bearer " { continue }
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        if let body = template["body"], !(body is NSNull) {
            if let text = body as? String { request.httpBody = Data(resolve(text).utf8) }
            else {
                func replace(_ item: Any) -> Any {
                    if let text = item as? String { return resolve(text) }
                    if let array = item as? [Any] { return array.map(replace) }
                    if let object = item as? [String: Any] { return object.mapValues(replace) }
                    return item
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: replace(body))
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        return request
    }

    private static func sensitive(_ key: String) -> Bool {
        let key = key.lowercased().replacingOccurrences(of: "-", with: "_")
        return ["authorization", "cookie", "api_key", "apikey", "access_token", "token", "secret", "x_api_key"].contains(key)
    }
    private static func checkSecretString(_ text: String) throws {
        if !text.isEmpty && !text.contains("{{apiKey}}") && !text.contains("{{cookie}}") {
            throw QuotaFailure.unavailable("请用 {{apiKey}} 或 {{cookie}} 引用凭据，不要写入脚本")
        }
    }
    private static func checkSecrets(_ object: Any) throws {
        if let values = object as? [String: Any] {
            for (key, value) in values {
                if sensitive(key), let text = value as? String { try checkSecretString(text) }
                try checkSecrets(value)
            }
        } else if let values = object as? [Any] {
            for value in values { try checkSecrets(value) }
        }
    }
}
