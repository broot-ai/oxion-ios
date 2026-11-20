import Foundation

struct APIError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

private struct ErrorBody: Decodable { let error: String? }

/// Пустой ответ вида {"ok": true}
struct OK: Decodable { let ok: Bool? }

extension Notification.Name {
    static let oxionUnauthorized = Notification.Name("oxionUnauthorized")
}

/// Клиент API сервера Oxion (тот же worker.js, что и у PWA).
enum API {
    static var token: String? {
        get { Keychain.get("token") }
        set { Keychain.set("token", newValue) }
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func url(_ path: String, query: [String: String] = [:]) -> URL {
        let full = AppSettings.serverURL.appendingPathComponent("api" + path)
        var c = URLComponents(url: full, resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return c.url ?? full
    }

    static func call<T: Decodable>(_ path: String,
                                   method: String = "GET",
                                   query: [String: String] = [:],
                                   body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.timeoutInterval = 25
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Нет связи с сервером. Проверьте интернет или включите VPN.", status: 0)
        }
        let (data, resp) = result
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

        if status >= 400 || status == 0 {
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.error ?? "Ошибка сервера (\(status))"
            if status == 401 {
                await MainActor.run {
                    NotificationCenter.default.post(name: .oxionUnauthorized, object: nil)
                }
            }
            throw APIError(message: msg, status: status)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "Не удалось прочитать ответ сервера", status: status)
        }
    }

    /// Сервер отдаёт ссылки на фото вида /media/...; превращаем в полный адрес.
    static func media(_ s: String?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: s, relativeTo: AppSettings.serverURL)?.absoluteURL
    }

    static func page(_ path: String) -> URL {
        AppSettings.serverURL.appendingPathComponent(path)
    }
}
