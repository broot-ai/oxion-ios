import Foundation
import UIKit
import MetricKit

// MARK: - Отчёты о вылетах
// При падении записываем причину и стек в файл, при следующем запуске отправляем на сервер (/api/crash).
// Дополнительно iOS через MetricKit присылает свои отчёты о вылетах — их тоже отправляем.

final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()
    private static var path: String = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("oxion-crash.json").path
    }()
    /// последние действия пользователя — помогают понять, где упало
    nonisolated(unsafe) static var trail: [String] = []

    static func mark(_ s: String) {
        trail.append(s)
        if trail.count > 25 { trail.removeFirst(trail.count - 25) }
    }

    static func install() {
        NSSetUncaughtExceptionHandler { e in
            CrashReporter.write(kind: "NSException \(e.name.rawValue)", reason: e.reason ?? "", stack: e.callStackSymbols)
        }
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGTRAP, SIGFPE] {
            signal(sig) { s in
                CrashReporter.write(kind: "signal \(s)", reason: CrashReporter.signalName(s), stack: Thread.callStackSymbols)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        MXMetricManager.shared.add(shared)
        Task { await sendPending() }
    }

    static func signalName(_ s: Int32) -> String {
        switch s {
        case SIGABRT: return "SIGABRT (abort / Swift fatalError / NSException)"
        case SIGILL: return "SIGILL"
        case SIGSEGV: return "SIGSEGV (bad memory access)"
        case SIGBUS: return "SIGBUS"
        case SIGTRAP: return "SIGTRAP (Swift runtime trap: index out of range, force unwrap nil…)"
        case SIGFPE: return "SIGFPE"
        default: return "signal \(s)"
        }
    }

    static func write(kind: String, reason: String, stack: [String]) {
        let d: [String: Any] = [
            "at": Int(Date().timeIntervalSince1970 * 1000),
            "kind": kind, "reason": reason,
            "stack": (["trail: " + trail.joined(separator: " → ")] + stack).joined(separator: "\n"),
            "build": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") + ")",
            "os": "iOS " + ProcessInfo.processInfo.operatingSystemVersionString,
            "screen": trail.last ?? ""
        ]
        if let data = try? JSONSerialization.data(withJSONObject: d) {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    static func sendPending() async {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if (try? await post(obj)) == true { try? FileManager.default.removeItem(atPath: path) }
    }

    private static func post(_ body: [String: Any]) async throws -> Bool {
        var req = URLRequest(url: AppSettings.serverURL.appendingPathComponent("api/crash"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = API.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // отчёты iOS (MetricKit) — приходят при следующем запуске
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                let json = String(data: c.jsonRepresentation(), encoding: .utf8) ?? ""
                let body: [String: Any] = [
                    "at": Int(Date().timeIntervalSince1970 * 1000),
                    "kind": "metrickit " + (c.exceptionType.map { "exc \($0)" } ?? "") + (c.signal.map { " sig \($0)" } ?? ""),
                    "reason": c.terminationReason ?? (c.exceptionReason?.composedMessage ?? ""),
                    "stack": json, "build": c.applicationVersion, "os": c.metaData.osVersion, "screen": "metrickit"
                ]
                Task { _ = try? await Self.post(body) }
            }
        }
    }
}
