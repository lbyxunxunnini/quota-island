import Foundation
import JavaScriptCore

@main
enum ApplicationEntry {
    static func main() {
        if CommandLine.arguments.contains("--quota-script-worker") {
            ScriptWorker.run()
        } else {
            AIQuotaIslandApp.main()
        }
    }
}

/// No native objects are exported into this JavaScript context.
/// The app kills this helper process if configuration evaluation or extraction hangs.
enum ScriptWorker {
    static func run() {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= 5_242_880,
                  let input = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let script = input["script"] as? String,
                  let action = input["action"] as? String, let context = JSContext() else {
                reply(["ok": false, "error": "脚本输入无效"])
                return
            }
            if action == "format" {
                try format(script, context: context)
                return
            }
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") || trimmed.hasSuffix(");") else {
                reply(["ok": false, "error": "配置必须用圆括号包裹为对象表达式"])
                return
            }
            context.evaluateScript("var __config = \(trimmed)\n;")
            guard context.exception == nil else {
                reply(["ok": false, "error": "脚本语法或配置执行错误，请检查括号和字段"])
                return
            }
            if action == "request" {
                context.evaluateScript("var __result = (__config && typeof __config.extractor === 'function') ? __config.request : undefined;")
            } else if action == "extract" {
                context.setObject(input["response"] ?? NSNull(), forKeyedSubscript: "__response" as NSString)
                context.evaluateScript("var __result = __config.extractor(__response);")
            } else {
                reply(["ok": false, "error": "未知脚本操作"])
                return
            }
            guard context.exception == nil,
                  let text = context.evaluateScript("JSON.stringify(__result)")?.toString(),
                  let resultData = text.data(using: .utf8), resultData.count <= 262_144,
                  let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                reply(["ok": false, "error": "脚本必须返回可序列化的对象，请检查 request 或 extractor"])
                return
            }
            reply(["ok": true, "result": result])
        } catch {
            reply(["ok": false, "error": "脚本运行未完成，请检查配置"])
        }
    }

    private static func format(_ script: String, context: JSContext) throws {
        for name in ["standalone", "babel", "estree"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Formatter") else {
                reply(["ok": false, "error": "格式化资源缺失，请重新安装 App"])
                return
            }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            guard context.exception == nil else {
                reply(["ok": false, "error": "格式化组件无法加载"])
                return
            }
        }
        context.setObject(script, forKeyedSubscript: "__input" as NSString)
        context.evaluateScript("""
        var __done = false, __formatted = null, __formatError = false;
        prettier.format(__input, {
          parser: "babel",
          plugins: [prettierPlugins.babel, prettierPlugins.estree],
          printWidth: 90, semi: true
        }).then(function (text) { __formatted = text; __done = true; },
                function () { __formatError = true; __done = true; });
        """)
        let deadline = Date().addingTimeInterval(20)
        while context.exception == nil && context.objectForKeyedSubscript("__done")?.toBool() != true && Date() < deadline {
            context.evaluateScript("void 0")
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        guard context.exception == nil,
              context.objectForKeyedSubscript("__formatError")?.toBool() != true,
              let text = context.objectForKeyedSubscript("__formatted")?.toString(), text != "null" else {
            reply(["ok": false, "error": "格式化失败，请检查 JavaScript 语法"])
            return
        }
        reply(["ok": true, "text": text])
    }

    private static func reply(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        FileHandle.standardOutput.write(data)
    }
}
