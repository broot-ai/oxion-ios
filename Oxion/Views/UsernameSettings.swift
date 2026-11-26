import SwiftUI

// MARK: - Имя пользователя как в Telegram
// Одно имя бесплатно, от 5 символов, a–z 0–9 _. Владельцы и администраторы — от 1 символа и несколько имён.

struct UsernameState: Decodable {
    let username: String?
    let extra: [Extra]
    let privileged: Bool
    let min: Int
    let max: Int
    let extraAllowed: Bool
    struct Extra: Decodable, Identifiable, Hashable {
        let username: String
        let active: Bool
        var id: String { username.lowercased() }
    }
}

private struct UsernameCheck: Decodable {
    let ok: Bool
    let empty: Bool?
    let mine: Bool?
    let error: String?
    let text: String?
}

struct UsernameSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var st: UsernameState?
    @State private var text = ""
    @State private var original = ""
    @State private var status: Status = .idle
    @State private var saving = false
    @State private var addExtra = false
    @State private var newExtra = ""
    @State private var editingOrder = false
    @State private var extras: [UsernameState.Extra] = []
    @FocusState private var focused: Bool

    enum Status: Equatable {
        case idle, checking
        case ok(String)
        case bad(String)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
    }
    private var changed: Bool { trimmed != original }
    private var canSave: Bool {
        guard changed, !saving else { return false }
        if trimmed.isEmpty { return !original.isEmpty }
        if case .ok = status { return true }
        return false
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("Имя пользователя", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { if canSave { Task { await save() } } }
                        .onChange(of: text) { _, v in
                            // как в Telegram: лишнее не даём ввести
                            let f = String(v.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(st?.max ?? 32))
                            if f != v { text = f }
                        }
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Имя пользователя")
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    statusLine
                    Text(st?.privileged == true
                         ? "Вы можете выбрать публичное имя пользователя в Oxion. Тогда другие люди смогут найти вас по этому имени и написать вам.\n\nМожно использовать a–z, 0–9 и подчёркивания. Как владельцу или администратору, вам доступны имена от 1 символа."
                         : "Вы можете выбрать публичное имя пользователя в Oxion. Тогда другие люди смогут найти вас по этому имени и написать вам.\n\nМожно использовать a–z, 0–9 и подчёркивания. Минимальная длина — 5 символов.")
                    if !original.isEmpty && trimmed == original {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Эта ссылка открывает ваш профиль:")
                            HStack(spacing: 14) {
                                Button {
                                    UIPasteboard.general.string = ProfileLink.string(original)
                                    Haptic.success()
                                    OxAlert.show(icon: "link", title: String(localized: "Ссылка скопирована"))
                                } label: {
                                    Text(ProfileLink.short(original)).foregroundStyle(Color.limeInk).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                ShareLink(item: ProfileLink.url(original)) {
                                    Image(systemName: "square.and.arrow.up").foregroundStyle(Color.limeInk)
                                }
                            }
                        }
                    }
                }
            }

            if st?.extraAllowed == true {
                Section {
                    ForEach(extras) { e in
                        Menu {
                            Button {
                                Task { await toggle(e) }
                            } label: {
                                Label(e.active ? "Скрыть из профиля" : "Показать в профиле", systemImage: e.active ? "eye.slash" : "eye")
                            }
                            Button {
                                UIPasteboard.general.string = "@" + e.username
                                Haptic.success()
                            } label: { Label("Скопировать", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { Task { await remove(e) } } label: {
                                Label("Освободить имя", systemImage: "trash")
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "at")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(e.active ? Color(hex: 0x0A84FF) : Color.gray, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("@" + e.username).foregroundStyle(.primary)
                                    Text(e.active ? "активно" : "неактивно")
                                        .font(.caption)
                                        .foregroundStyle(e.active ? Color(hex: 0x0A84FF) : .secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                    .onMove { from, to in
                        extras.move(fromOffsets: from, toOffset: to)
                        Task { await saveOrder() }
                    }
                    Button {
                        newExtra = ""
                        addExtra = true
                    } label: {
                        Label("Добавить имя", systemImage: "plus.circle.fill").foregroundStyle(Color.limeInk)
                    }
                } header: {
                    HStack {
                        Text("Дополнительные имена")
                        Spacer()
                        if extras.count > 1 {
                            Button(editingOrder ? "Готово" : "Порядок") { withAnimation { editingOrder.toggle() } }
                                .font(.caption.bold())
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text("Доступно только владельцам и администраторам. Активные имена видны в профиле, и по ним вас можно найти. Порядок меняется перетаскиванием.")
                }
            }
        }
        .environment(\.editMode, .constant(editingOrder ? .active : .inactive))
        .navigationTitle("Имя пользователя")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if saving {
                    ProgressView()
                } else {
                    Button("Готово") { Task { await save() } }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
        }
        .task { await load() }
        .task(id: trimmed) { await check() }
        .alert("Новое имя", isPresented: $addExtra) {
            TextField("username", text: $newExtra)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Отмена", role: .cancel) {}
            Button("Добавить") { Task { await add() } }
        } message: {
            Text("Латинские буквы, цифры и подчёркивания.")
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .idle: EmptyView()
        case .checking:
            Text("Проверка имени…").foregroundStyle(.secondary)
        case .ok(let t):
            Text(t).foregroundStyle(Color(hex: 0x34C759))
        case .bad(let t):
            Text(t).foregroundStyle(Color(hex: 0xFF3B30))
        }
    }

    // MARK: логика
    private func apply(_ s: UsernameState) {
        st = s
        extras = s.extra
    }

    private func load() async {
        do {
            let s: UsernameState = try await API.call("/usernames")
            apply(s)
            original = s.username ?? ""
            if text.isEmpty { text = original }
            if !original.isEmpty { status = .idle }
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func check() async {
        let u = trimmed
        if u.isEmpty || u == original { status = .idle; return }
        // мгновенные подсказки без сервера
        let min = st?.min ?? 5
        if u.first?.isNumber == true { status = .bad(String(localized: "Имя пользователя не может начинаться с цифры.")); return }
        if u.count < min {
            status = .bad(String(localized: "Имя пользователя должно содержать минимум 5 символов."))
            return
        }
        status = .checking
        try? await Task.sleep(for: .milliseconds(450))
        if Task.isCancelled { return }
        do {
            let r: UsernameCheck = try await API.call("/usernames/check", query: ["u": u])
            if Task.isCancelled { return }
            if r.empty == true { status = .idle }
            else if r.ok { status = .ok(r.mine == true ? String(localized: "Это ваше имя пользователя.") : "\(u) — " + String(localized: "свободно.")) }
            else { status = .bad(r.error ?? String(localized: "Это имя пользователя уже занято.")) }
        } catch {
            if !Task.isCancelled { status = .bad(error.localizedDescription) }
        }
    }

    private func save() async {
        guard canSave else { return }
        saving = true
        defer { saving = false }
        do {
            let s: UsernameState = try await API.call("/usernames/main", method: "POST", body: ["username": trimmed])
            apply(s)
            original = s.username ?? ""
            text = original
            status = .idle
            Haptic.success()
            await model.loadMe()
            dismiss()
        } catch {
            Haptic.error()
            status = .bad(error.localizedDescription)
        }
    }

    private func add() async {
        let u = newExtra.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard !u.isEmpty else { return }
        do {
            let s: UsernameState = try await API.call("/usernames/extra", method: "POST", body: ["username": u])
            withAnimation { apply(s) }
            Haptic.success()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func toggle(_ e: UsernameState.Extra) async {
        do {
            let s: UsernameState = try await API.call("/usernames/extra/toggle", method: "POST", body: ["username": e.username, "active": !e.active])
            withAnimation { apply(s) }
            Haptic.tap()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func remove(_ e: UsernameState.Extra) async {
        do {
            let s: UsernameState = try await API.call("/usernames/extra/delete", method: "POST", body: ["username": e.username])
            withAnimation { apply(s) }
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func saveOrder() async {
        let _: UsernameState? = try? await API.call("/usernames/extra/order", method: "POST", body: ["order": extras.map { $0.username }])
    }
}

// MARK: - Ссылка на профиль по имени: …/@username (как t.me/username)

extension Notification.Name {
    static let oxionOpenRoute = Notification.Name("oxionOpenRoute")
}

enum ProfileLink {
    /// полная ссылка для «Поделиться»
    static func url(_ username: String) -> URL {
        URL(string: AppSettings.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/@" + username)!
    }
    static func string(_ username: String) -> String { url(username).absoluteString }
    /// красиво для подписи: fit-app…/@name
    static func short(_ username: String) -> String {
        (AppSettings.serverURL.host ?? "oxion") + "/@" + username
    }

    /// маршрут внутри приложения для своей ссылки: oxion://u/имя, oxion://user/12, https://наш-сервер/@имя, …/u/имя
    static func route(for url: URL) -> String? {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "oxion" {
            let host = url.host ?? ""
            let rest = url.pathComponents.filter { $0 != "/" }
            if (host == "u" || host == "user"), let first = rest.first { return host + "/" + first }
            if host == "post", let first = rest.first, Int(first) != nil { return "post/" + first }
            if host.hasPrefix("@") { return "u/" + host.dropFirst() }
            return nil
        }
        guard scheme == "http" || scheme == "https",
              let h = url.host?.lowercased(), h == AppSettings.serverURL.host?.lowercased() else { return nil }
        let p = url.pathComponents.filter { $0 != "/" }
        if p.count == 1, p[0].hasPrefix("@"), p[0].count > 1 { return "u/" + p[0].dropFirst() }
        if p.count == 2, p[0] == "u" { return "u/" + p[1] }
        // ссылка на ветку: …/t/123 и старая …/#post/123
        if p.count == 2, p[0] == "t", Int(p[1]) != nil { return "post/" + p[1] }
        if let f = url.fragment, f.hasPrefix("post/"), Int(f.dropFirst(5)) != nil { return f }
        return nil
    }
}
