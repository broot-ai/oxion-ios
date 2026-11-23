import SwiftUI
import AuthenticationServices
import CryptoKit
import LocalAuthentication
import Security

// Вход без SMS и пароля.
// 1) Ключ устройства: закрытый ключ P-256 живёт в Secure Enclave (защищённый чип iPhone) и открывается только по Face ID / Touch ID.
//    Работает с бесплатным Apple ID.
// 2) Passkey (WebAuthn, AuthenticationServices): синхронизируется через «Связку ключей iCloud» на все устройства.
//    Нужна привязка домена (Associated Domains: webcredentials) — она доступна только в Apple Developer Program ($99).
// У одного аккаунта может быть несколько ключей: по одному на каждое устройство и сколько угодно passkey.

struct KeyChallenge: Decodable { let challenge: String; let rpId: String }
struct KeyBegin: Decodable {
    let challenge: String
    let rpId: String
    let userId: String
    let userName: String
    let displayName: String
    let exclude: [String]
}
struct LoginKey: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let name: String?
    let createdAt: Double?
    let lastUsed: Double?
}
struct LoginKeysResponse: Decodable { let items: [LoginKey] }
struct KeyLoginResponse: Decodable { let status: String; let token: String? }

enum LoginKeyError: LocalizedError {
    case noBiometry, noEnclave, cancelled, needsPaid, failed(String)
    var errorDescription: String? {
        switch self {
        case .noBiometry: "На устройстве не настроен Face ID или Touch ID"
        case .noEnclave: "На этом устройстве нет Secure Enclave"
        case .cancelled: "Отменено"
        case .needsPaid: "Passkey в iCloud заработает после подписки Apple Developer ($99) — нужна привязка домена. Пока используйте вход по Face ID / Touch ID на этом устройстве."
        case .failed(let t): t
        }
    }
}

enum Biometry {
    static var kind: LABiometryType {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return c.biometryType
    }
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }
    static var name: String {
        switch kind {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "биометрия"
        }
    }
    static var icon: String {
        switch kind {
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "faceid"
        }
    }
}

extension Data {
    var b64u: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(b64u: String) {
        var s = b64u.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
    init?(hex: String) {
        var d = Data(); var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            d.append(b); i = j
        }
        self = d
    }
}

// MARK: - Ключ устройства (Secure Enclave)

enum DeviceLoginKey {
    private static let service = "ru.oxion.devicekey"
    private struct Stored: Codable { let id: String; let key: Data; let userName: String? }

    private static func read() -> Stored? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "key", kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: d)
    }

    private static func write(_ s: Stored) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "key"]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = try? JSONEncoder().encode(s)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static var exists: Bool { read() != nil }
    static var serverId: String? { read().map { "dev_" + $0.id } }
    static var userName: String? { read()?.userName }

    static func remove() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "key"] as CFDictionary)
    }

    private static func authenticate(_ reason: String) async throws -> LAContext {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Отмена"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { throw LoginKeyError.noBiometry }
        do {
            try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
            throw LoginKeyError.cancelled
        }
        return ctx
    }

    /// Создать ключ на этом устройстве и привязать к аккаунту (нужен вход)
    @MainActor
    static func register(name: String) async throws {
        guard SecureEnclave.isAvailable else { throw LoginKeyError.noEnclave }
        let begin: KeyBegin = try await API.call("/me/keys/begin", method: "POST")
        let ctx = try await authenticate("Включить вход в OXION по \(Biometry.name)")
        var err: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet], &err) else {
            throw LoginKeyError.failed("Не удалось создать защищённый ключ")
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: ctx)
        guard let ch = Data(hex: begin.challenge) else { throw LoginKeyError.failed("Неверный ответ сервера") }
        let sig = try key.signature(for: ch)
        let id = UUID().uuidString.lowercased()
        let _: OK = try await API.call("/me/keys", method: "POST", body: [
            "kind": "device", "key_id": id, "name": name, "challenge": begin.challenge,
            "public_key": key.publicKey.x963Representation.b64u, "signature": sig.rawRepresentation.b64u,
        ])
        write(Stored(id: id, key: key.dataRepresentation, userName: begin.displayName))
    }

    /// Вход по Face ID / Touch ID — возвращает токен сессии
    @MainActor
    static func login() async throws -> String {
        guard let s = read() else { throw LoginKeyError.failed("На этом устройстве нет ключа входа") }
        let ch: KeyChallenge = try await API.call("/auth/key/challenge", method: "POST")
        let ctx = try await authenticate("Вход в OXION")
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: s.key, authenticationContext: ctx)
        guard let data = Data(hex: ch.challenge) else { throw LoginKeyError.failed("Неверный ответ сервера") }
        let sig = try key.signature(for: data)
        do {
            let r: KeyLoginResponse = try await API.call("/auth/key/login", method: "POST", body: [
                "key_id": "dev_" + s.id, "challenge": ch.challenge, "signature": sig.rawRepresentation.b64u,
            ])
            guard let t = r.token else { throw LoginKeyError.failed("Сервер не выдал вход") }
            return t
        } catch {
            if error.localizedDescription.contains("Ключ не найден") { remove() }
            throw error
        }
    }
}

// MARK: - Passkey (AuthenticationServices / WebAuthn)

@MainActor
final class PasskeyFlow: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var cont: CheckedContinuation<ASAuthorization, Error>?
    private var keep: PasskeyFlow?

    private func run(_ req: ASAuthorizationRequest, immediate: Bool = false) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { c in
            cont = c
            keep = self
            let ctl = ASAuthorizationController(authorizationRequests: [req])
            ctl.delegate = self
            ctl.presentationContextProvider = self
            if immediate { ctl.performRequests(options: .preferImmediatelyAvailableCredentials) } else { ctl.performRequests() }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization a: ASAuthorization) {
        MainActor.assumeIsolated { cont?.resume(returning: a); cont = nil; keep = nil }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            let ns = error as NSError
            let mapped: Error
            if let e = error as? ASAuthorizationError, e.code == .canceled { mapped = LoginKeyError.cancelled }
            else if ns.domain == "com.apple.AuthenticationServices.AuthorizationError", ns.code == 1004 || ns.code == 1000 { mapped = LoginKeyError.needsPaid }
            else if ns.localizedDescription.lowercased().contains("associated") || ns.localizedDescription.lowercased().contains("not associated") { mapped = LoginKeyError.needsPaid }
            else { mapped = error }
            cont?.resume(throwing: mapped); cont = nil; keep = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    /// Создать passkey для аккаунта (нужен вход)
    static func register(name: String) async throws {
        let b: KeyBegin = try await API.call("/me/keys/begin", method: "POST")
        let p = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: b.rpId)
        let req = p.createCredentialRegistrationRequest(challenge: Data(hex: b.challenge) ?? Data(),
                                                        name: b.userName, userID: Data(b.userId.utf8))
        req.displayName = b.displayName
        req.excludedCredentials = b.exclude.compactMap { Data(b64u: $0) }.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        let a = try await PasskeyFlow().run(req)
        guard let c = a.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let att = c.rawAttestationObject else { throw LoginKeyError.failed("Система не вернула ключ") }
        let _: OK = try await API.call("/me/keys", method: "POST", body: [
            "kind": "webauthn", "name": name, "attestation_object": att.b64u, "client_data": c.rawClientDataJSON.b64u,
        ])
    }

    /// Вход по passkey из «Связки ключей iCloud»
    static func login() async throws -> String {
        let ch: KeyChallenge = try await API.call("/auth/key/challenge", method: "POST")
        let p = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: ch.rpId)
        let req = p.createCredentialAssertionRequest(challenge: Data(hex: ch.challenge) ?? Data())
        let a = try await PasskeyFlow().run(req)
        guard let c = a.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else { throw LoginKeyError.failed("Система не вернула подпись") }
        let r: KeyLoginResponse = try await API.call("/auth/key/login", method: "POST", body: [
            "key_id": c.credentialID.b64u, "client_data": c.rawClientDataJSON.b64u,
            "authenticator_data": c.rawAuthenticatorData.b64u, "signature": c.signature.b64u,
        ])
        guard let t = r.token else { throw LoginKeyError.failed("Сервер не выдал вход") }
        return t
    }
}

// MARK: - Экран «Ключи входа»

struct LoginKeysView: View {
    @State private var keys: [LoginKey] = []
    @State private var loading = true
    @State private var busy = false
    @State private var renaming: LoginKey?
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: Biometry.icon).font(.system(size: 34)).foregroundStyle(Color.limeInk)
                    Text("Вход без SMS и пароля").font(.title3.bold())
                    Text("Ключ хранится в защищённом чипе устройства и открывается только вашим лицом или пальцем. Серверу OXION передаётся лишь открытая часть ключа.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section {
                Button { Task { await addDevice() } } label: {
                    Label(DeviceLoginKey.exists ? "Пересоздать ключ \(Biometry.name) на этом устройстве" : "Вход по \(Biometry.name) на этом устройстве",
                          systemImage: Biometry.icon)
                }
                .disabled(busy || !Biometry.available)
                Button { Task { await addPasskey() } } label: {
                    Label("Passkey в «Связке ключей iCloud»", systemImage: "person.badge.key.fill")
                }
                .disabled(busy)
            } header: {
                Text("Добавить")
            } footer: {
                Text(Biometry.available ? "Passkey синхронизируется на все ваши устройства Apple. Для него нужна подписка Apple Developer у владельца приложения." : "Настройте Face ID или Touch ID в «Настройках» iPhone.")
            }
            Section("Мои ключи") {
                if loading {
                    ProgressView()
                } else if keys.isEmpty {
                    Text("Ключей пока нет").foregroundStyle(.secondary)
                }
                ForEach(keys) { k in
                    HStack(spacing: 12) {
                        Image(systemName: k.kind == "device" ? "iphone.gen3" : "key.icloud.fill")
                            .foregroundStyle(Color.limeInk).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(k.name ?? "Ключ").font(.body.weight(.semibold))
                                if k.id == DeviceLoginKey.serverId {
                                    Text("это устройство").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.lime.opacity(0.25), in: Capsule())
                                }
                            }
                            Text(sub(k)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await delete(k) } } label: { Label("Удалить", systemImage: "trash") }
                        Button { newName = k.name ?? ""; renaming = k } label: { Label("Имя", systemImage: "pencil") }.tint(.gray)
                    }
                    .contextMenu {
                        Button { newName = k.name ?? ""; renaming = k } label: { Label("Переименовать", systemImage: "pencil") }
                        Button(role: .destructive) { Task { await delete(k) } } label: { Label("Удалить", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("Ключи входа")
        .task { await load() }
        .oxRefreshable { await load() }
        .alert("Название ключа", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Например, iPhone 17 Pro", text: $newName)
            Button("Сохранить") { if let k = renaming { Task { await rename(k) } } }
            Button("Отмена", role: .cancel) { renaming = nil }
        }
    }

    private func sub(_ k: LoginKey) -> String {
        let f = Date.FormatStyle(date: .abbreviated, time: .omitted)
        var s = k.kind == "device" ? "Face ID / Touch ID" : "Passkey iCloud"
        if let c = k.createdAt { s += " · создан " + Date(timeIntervalSince1970: c / 1000).formatted(f) }
        if let u = k.lastUsed { s += " · вход " + Date(timeIntervalSince1970: u / 1000).formatted(f) }
        return s
    }

    private func load() async {
        if let r: LoginKeysResponse = try? await API.call("/me/keys") { keys = r.items }
        loading = false
    }

    private func addDevice() async {
        busy = true; defer { busy = false }
        do {
            try await DeviceLoginKey.register(name: UIDevice.current.name)
            Haptic.success()
            OxAlert.show(icon: Biometry.icon, title: "Готово", message: "Теперь можно входить по \(Biometry.name).")
            await load()
        } catch LoginKeyError.cancelled {
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func addPasskey() async {
        busy = true; defer { busy = false }
        do {
            try await PasskeyFlow.register(name: "Passkey · \(UIDevice.current.model)")
            Haptic.success()
            await load()
        } catch LoginKeyError.cancelled {
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func delete(_ k: LoginKey) async {
        do {
            let _: OK = try await API.call("/me/keys/\(k.id)", method: "DELETE")
            if k.id == DeviceLoginKey.serverId { DeviceLoginKey.remove() }
            keys.removeAll { $0.id == k.id }
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func rename(_ k: LoginKey) async {
        let n = newName.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !n.isEmpty else { return }
        do {
            let _: OK = try await API.call("/me/keys/\(k.id)", method: "PATCH", body: ["name": n])
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

/// Предложение создать ключ сразу после входа или регистрации
struct LoginKeyOfferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: Biometry.icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.limeInk)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.top, 28)
            Text("Входить по \(Biometry.name)?").font(.title2.bold())
            Text("В следующий раз войдёте за секунду — без Telegram, SMS и паролей. Ключ остаётся только на этом устройстве.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            Button {
                Task {
                    busy = true
                    do {
                        try await DeviceLoginKey.register(name: UIDevice.current.name)
                        Haptic.success()
                        dismiss()
                    } catch LoginKeyError.cancelled {
                    } catch { OxAlert.error(error.localizedDescription) }
                    busy = false
                }
            } label: {
                HStack { if busy { ProgressView() }; Text("Включить") }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
            .disabled(busy)
            Button("Не сейчас") { dismiss() }.foregroundStyle(.secondary).padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.medium])
        .onAppear { UserDefaults.standard.set(true, forKey: "ox.keyOffered") }
    }

    static var shouldOffer: Bool {
        Biometry.available && SecureEnclave.isAvailable && !DeviceLoginKey.exists && !UserDefaults.standard.bool(forKey: "ox.keyOffered")
    }
}
