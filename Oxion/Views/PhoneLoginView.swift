import SwiftUI

// MARK: - Вход и привязка номера через Telegram Gateway:
// код из 6 цифр приходит в Telegram от официального аккаунта «Verification Codes».

private struct PhoneStart: Decodable { let requestId: String; let phone: String; let ttl: Int?; let length: Int? }
private struct PhoneToken: Decodable { let token: String; let created: Bool? }
private struct PhoneLinked: Decodable { let ok: Bool?; let phone: String? }
struct MyPhone: Decodable { let phone: String? }

struct PhoneVerifyView: View {
    enum Mode { case login, link }
    let mode: Mode
    var onLinked: (String) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var phone = "+7 "
    @State private var code = ""
    @State private var request: PhoneStart?
    @State private var busy = false
    @State private var errorText: String?
    @State private var resendIn = 0
    @FocusState private var focus: Field?
    enum Field { case phone, code }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: request == nil ? "phone.badge.checkmark" : "paperplane.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(Color.lime)
                    .contentTransition(.symbolEffect(.replace))
                Text(request == nil ? "Ваш номер телефона" : "Код в Telegram")
                    .font(.title.bold())
                Text(request == nil
                     ? "Пришлём код подтверждения в Telegram — от официального аккаунта «Verification Codes». СМС не нужны."
                     : "Отправили код на \(request!.phone). Откройте Telegram: код придёт от «Verification Codes».")
                    .foregroundStyle(Color.oxHint)
                    .fixedSize(horizontal: false, vertical: true)

                if request == nil {
                    TextField("+7 900 000-00-00", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.title2.monospacedDigit().bold())
                        .padding(14)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .focused($focus, equals: .phone)
                } else {
                    CodeBoxes(code: $code, length: request?.length ?? 6)
                        .focused($focus, equals: .code)
                        .onChange(of: code) {
                            code = String(code.filter(\.isNumber).prefix(request?.length ?? 6))
                            if code.count == (request?.length ?? 6) { Task { await verify() } }
                        }
                    HStack {
                        Button("Изменить номер") { withAnimation { request = nil; code = "" } }
                        Spacer()
                        Button(resendIn > 0 ? "Повторить через \(resendIn) с" : "Отправить ещё раз") {
                            Task { await send() }
                        }
                        .disabled(resendIn > 0 || busy)
                    }
                    .font(.subheadline)
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Color(hex: 0xFF5A4E))
                }
                Spacer()
                Button {
                    Task { request == nil ? await send() : await verify() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.black) }
                        Text(request == nil ? "Получить код" : "Подтвердить")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.lime)
                .foregroundStyle(.black)
                .disabled(busy || (request == nil ? digits.count < 10 : code.count < (request?.length ?? 6)))
            }
            .padding(20)
            .background(Color.oxBg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .onAppear { focus = .phone }
            .task(id: resendIn) {
                guard resendIn > 0 else { return }
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }

    private var digits: String { phone.filter(\.isNumber) }

    private func send() async {
        errorText = nil
        busy = true
        defer { busy = false }
        do {
            let path = mode == .login ? "/login/phone/start" : "/me/phone/start"
            let r: PhoneStart = try await API.call(path, method: "POST", body: ["phone": phone])
            withAnimation { request = r }
            code = ""
            resendIn = 60
            focus = .code
            Haptic.tap()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func verify() async {
        guard let req = request, !busy else { return }
        errorText = nil
        busy = true
        defer { busy = false }
        do {
            if mode == .login {
                let r: PhoneToken = try await API.call("/login/phone/verify", method: "POST", body: ["request_id": req.requestId, "code": code])
                Haptic.success()
                dismiss()
                await model.loggedIn(token: r.token)
            } else {
                let r: PhoneLinked = try await API.call("/me/phone/verify", method: "POST", body: ["request_id": req.requestId, "code": code])
                Haptic.success()
                onLinked(r.phone ?? phone)
                dismiss()
            }
        } catch {
            errorText = error.localizedDescription
            code = ""
            OxHaptics.play(.select)
        }
    }
}

/// Шесть клеточек для кода (само поле скрыто; iOS подставит код из буфера/подсказки клавиатуры)
private struct CodeBoxes: View {
    @Binding var code: String
    let length: Int

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(height: 56)
            HStack(spacing: 8) {
                ForEach(0..<length, id: \.self) { i in
                    let ch = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                    Text(ch)
                        .font(.title.monospacedDigit().bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(i == code.count ? Color.lime : Color.white.opacity(0.08), lineWidth: i == code.count ? 2 : 1))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Профиль → «Номер телефона»
struct PhoneSettingsView: View {
    @State private var phone: String?
    @State private var loaded = false
    @State private var link = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label(phone ?? "Не привязан", systemImage: "phone.fill")
                    Spacer()
                    if phone != nil { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.lime) }
                }
                Button(phone == nil ? "Привязать номер" : "Сменить номер") { link = true }
                if phone != nil {
                    Button("Отвязать номер", role: .destructive) {
                        OxAlert.confirm(title: "Отвязать номер?", message: "Войти по номеру в этот аккаунт будет нельзя, пока не привяжете снова.",
                                        action: "Отвязать", destructive: true) {
                            Task {
                                let _: OK? = try? await API.call("/me/phone", method: "DELETE")
                                phone = nil
                            }
                        }
                    }
                }
            } footer: {
                Text("С привязанным номером можно входить в этот же аккаунт без бота: код придёт в Telegram. Номер не показывается другим людям.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.oxBg)
        .navigationTitle("Номер телефона")
        .task {
            if let r: MyPhone = try? await API.call("/me/phone") { phone = r.phone }
            loaded = true
        }
        .sheet(isPresented: $link) {
            PhoneVerifyView(mode: .link) { p in phone = p }
        }
    }
}
