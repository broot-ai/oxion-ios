import Foundation
import UIKit

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

    private static func request(_ path: String, method: String, query: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.timeoutInterval = 30
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return req
    }

    static func call<T: Decodable>(_ path: String,
                                   method: String = "GET",
                                   query: [String: String] = [:],
                                   body: [String: Any]? = nil) async throws -> T {
        var req = request(path, method: method, query: query)
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await send(req)
    }

    /// Отправка файла (фото) формой multipart/form-data
    static func upload<T: Decodable>(_ path: String,
                                     fields: [String: String] = [:],
                                     fileField: String = "file",
                                     data: Data,
                                     filename: String = "photo.jpg",
                                     mime: String = "image/jpeg") async throws -> T {
        var req = request(path, method: "POST")
        req.timeoutInterval = 90
        let boundary = "oxion-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var b = Data()
        for (k, v) in fields {
            b.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".utf8))
        }
        b.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        b.append(data)
        b.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = b
        return try await send(req)
    }

    private static func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Нет связи с сервером. Проверьте интернет или включите VPN.", status: 0)
        }
        let (data, resp) = result
        Traffic.add(data.count + (req.httpBody?.count ?? 0) + 400, .api)
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

    /// Сжимаем фото перед отправкой: не больше 2000 px по длинной стороне, JPEG.
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 2000) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return img.jpegData(compressionQuality: 0.82)
    }
}
