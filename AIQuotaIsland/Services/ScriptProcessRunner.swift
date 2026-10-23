import Darwin
import Foundation

private final class ScriptProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private(set) var timedOut = false

    func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if stopped { throw CancellationError() }
        self.process = process
        try process.run()
    }
    func stop(timeout: Bool = false) {
        lock.lock()
        stopped = true
        timedOut = timedOut || timeout
        let process = process
        lock.unlock()
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    func didTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}

enum ScriptProcessRunner {
    static func run(_ payload: [String: Any], timeout: Double) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard data.count <= 5_242_880 else { throw QuotaFailure.unavailable("脚本或响应过大") }
        let control = ScriptProcessControl()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = Bundle.main.executableURL
                    process.arguments = ["--quota-script-worker"]
                    process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
                    let input = Pipe()
                    let output = Pipe()
                    process.standardInput = input
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    let deadline = DispatchWorkItem { control.stop(timeout: true) }
                    do {
                        try control.launch(process)
                        DispatchQueue.global().asyncAfter(deadline: .now() + min(60, max(1, timeout)), execute: deadline)
                        try input.fileHandleForWriting.write(contentsOf: data)
                        try input.fileHandleForWriting.close()
                        let result = output.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        deadline.cancel()
                        if control.didTimeout() { throw QuotaFailure.unavailable("脚本执行超时，已终止；请检查死循环或缩短计算") }
                        guard process.terminationStatus == 0, result.count <= 524_288,
                              let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any] else {
                            throw QuotaFailure.unavailable("脚本执行未返回有效结果")
                        }
                        guard object["ok"] as? Bool == true else {
                            throw QuotaFailure.unavailable(object["error"] as? String ?? "脚本执行失败")
                        }
                        continuation.resume(returning: object)
                    } catch {
                        deadline.cancel()
                        control.stop()
                        continuation.resume(throwing: control.didTimeout()
                            ? QuotaFailure.unavailable("脚本执行超时，已终止") : error)
                    }
                }
            }
        } onCancel: { control.stop() }
    }
}
