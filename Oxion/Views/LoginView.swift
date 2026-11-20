import SwiftUI

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
                .controlSize(.large)
                .disabled(busy)

                Button("Войти по коду из бота") {
                    showCode = true
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                if busy {
                    Button("Отменить") {
                        pollTask?.cancel()
                        busy = false
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
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
    }

    private func startLogin() async {
        errorText = nil
        busy = true
        Haptic.tap()
        do {
            let s: LoginStart = try await API.call("/login/start", method: "POST", body: [:])
            if let url = URL(string: s.link) { openURL(url) }
            pollTask?.cancel()
            let token = s.token
            pollTask = Task { await poll(token: token) }
        } catch {
            errorText = error.localizedDescription
            busy = false
        }
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
