import SwiftUI
import AuthenticationServices

/// Вход через Telegram-бота: приложение создаёт заявку, человек подтверждает её в боте,
/// приложение каждые 2 секунды спрашивает сервер, подтверждено ли.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var busy = false
    @State private var errorText: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var showCode = false
    @State private var code = ""
    @State private var phoneLogin = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color.lime.opacity(0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                FlameMark(size: 96)
                Text("Oxion")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Тренеры, тренировки и прогресс\nв одном приложении")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if hasKey {
                    Button {
                        Task { await keyLogin() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: Biometry.icon)
                            Text("Войти по \(Biometry.name)")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.lime)
                    .foregroundStyle(Color.onLime)
                    .disabled(busy)
                }

                Button {
                    Task { await startLogin() }
                } label: {
                    HStack(spacing: 10) {
                        if busy {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(busy ? "Подтвердите вход в Telegram…" : "Войти через Telegram")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .disabled(busy)

                SignInWithAppleButton(.signIn) { req in
                    req.requestedScopes = [.fullName]
                } onCompletion: { result in
                    Task { await appleLogin(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 46)
                .clipShape(Capsule())

                HStack(spacing: 10) {
                    Button {
                        phoneLogin = true
                    } label: {
                        Label("По номеру", systemImage: "phone.fill").frame(maxWidth: .infinity)
                    }
                    Button {
                        showCode = true
                    } label: {
                        Label("Код из бота", systemImage: "number").frame(maxWidth: .infinity)
                    }
                    Button {
                        Task { await passkeyLogin() }
                    } label: {
                        Label("Passkey", systemImage: "person.badge.key.fill").frame(maxWidth: .infinity)
                    }
                }
                .font(.subheadline.bold())
                .lineLimit(1)
                .buttonStyle(.glass)

                if busy {
                    Button("Отменить") {
                        pollTask?.cancel()
                        busy = false
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                LegalConsentLine().padding(.top, 4)
            }
            .padding(24)
        }
        .alert("Код из бота", isPresented: $showCode) {
            TextField("8 цифр", text: $code)
                .keyboardType(.numberPad)
            Button("Войти") {
                Task { await loginByCode() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Отправьте боту команду /code и введите полученный код")
        }
        .onDisappear { pollTask?.cancel() }
        .sheet(isPresented: $phoneLogin) { PhoneVerifyView(mode: .login) }
    }

    private struct AppleToken: Decodable { let token: String }

    private func appleLogin(_ result: Result<ASAuthorization, Error>) async {
        errorText = nil
        switch result {
        case .failure(let e):
            let code = (e as? ASAuthorizationError)?.code
            if code == .canceled { return }
            errorText = code == .unknown
                ? "Вход через Apple работает в версии из TestFlight или App Store."
                : e.localizedDescription
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.identityToken, let jwt = String(data: data, encoding: .utf8) else {
                errorText = "Apple не прислал токен входа"
                return
            }
            let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            do {
                let r: AppleToken = try await API.call("/login/apple", method: "POST", body: ["token": jwt, "name": name])
                await model.loggedIn(token: r.token)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func startLogin() async {
        errorText = nil
        busy = true
        Haptic.tap()
        do {
            let s: LoginStart = try await API.call("/login/start", method: "POST", body: [:])
            // вход — сразу в Telegram, минуя внутренний браузер
            if let url = URL(string: s.link) { openTelegram(url) }
            pollTask?.cancel()
            let token = s.token
            pollTask = Task { await poll(token: token) }
        } catch {
            errorText = error.localizedDescription
            busy = false
        }
    }

    @State private var hasKey = DeviceLoginKey.exists

    private func keyLogin() async {
        errorText = nil
        do {
            let t = try await DeviceLoginKey.login()
            await model.loggedIn(token: t)
        } catch LoginKeyError.cancelled {
        } catch {
            errorText = error.localizedDescription
            hasKey = DeviceLoginKey.exists
        }
    }

    private func passkeyLogin() async {
        errorText = nil
        do {
            let t = try await PasskeyFlow.login()
            await model.loggedIn(token: t)
        } catch LoginKeyError.cancelled {
        } catch { errorText = error.localizedDescription }
    }

    private func poll(token: String) async {
        for _ in 0..<300 {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            do {
                let r: LoginPoll = try await API.call("/login/poll", method: "POST", body: ["token": token])
                if r.status == "ok", let t = r.token {
                    busy = false
                    await model.loggedIn(token: t)
                    return
                }
                if r.status == "expired" {
                    errorText = "Время на вход истекло. Нажмите «Войти» ещё раз."
                    busy = false
                    return
                }
            } catch {
                // сеть пропала на секунду — пробуем дальше
            }
        }
        busy = false
    }

    private func loginByCode() async {
        errorText = nil
        do {
            let r: TokenResponse = try await API.call("/login", method: "POST", body: ["code": code])
            code = ""
            await model.loggedIn(token: r.token)
        } catch {
            errorText = error.localizedDescription
        }
    }
}


/// Открыть ссылку входа в приложении Telegram (tg://), а если его нет — в Safari
@MainActor
func openTelegram(_ url: URL) {
    var tg: URL?
    if (url.host ?? "").lowercased().hasSuffix("t.me"), let c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
        let parts = c.path.split(separator: "/").map(String.init)
        if let bot = parts.first {
            var t = URLComponents(string: "tg://resolve")!
            t.queryItems = [URLQueryItem(name: "domain", value: bot)] + (c.queryItems ?? [])
            tg = t.url
        }
    }
    if let tg, UIApplication.shared.canOpenURL(tg) {
        UIApplication.shared.open(tg)
    } else {
        UIApplication.shared.open(url, options: [.universalLinksOnly: false])
    }
}
