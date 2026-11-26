import SwiftUI

// MARK: - Официальная отметка OXION (как «галочка Telegram» слева от имени)
// Лаймовая «розетка» с огоньком. Выдаётся сотрудникам OXION и личным тренерам, прошедшим проверку.
// Нажатие на отметку открывает окно-объяснение, как у коллекционных имён в Telegram.

struct OxOfficial: Codable, Hashable {
    let kind: String            // staff | trainer | official
    let title: String?
    let since: Double?

    var headline: String {
        switch kind {
        case "trainer": return String(localized: "личный тренер, проверенный OXION")
        case "official": return String(localized: "официальный аккаунт OXION")
        default: return String(localized: "сотрудник команды OXION")
        }
    }
    var footnote: String {
        switch kind {
        case "trainer": return String(localized: "Тренер прошёл проверку OXION: личность, документы и квалификация подтверждены.")
        default: return String(localized: "Этот аккаунт подтверждён как официальный представителями OXION.")
        }
    }
}

/// Форма «розетки»: круг с мягкими зубцами
struct RosetteShape: Shape {
    var bumps = 10
    var depth: CGFloat = 0.075
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        var p = Path()
        let steps = 240
        for i in 0...steps {
            let a = CGFloat(i) / CGFloat(steps) * .pi * 2
            let r = R * (1 - depth * (1 - cos(CGFloat(bumps) * a)) / 2)
            let pt = CGPoint(x: c.x + r * cos(a - .pi / 2), y: c.y + r * sin(a - .pi / 2))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Отметка: лаймовая розетка + огонёк. animated — огонёк «живой» (для профиля и окна)
struct OxionSeal: View {
    var size: CGFloat = 20
    var animated = false

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                seal(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            seal(t: 0)
        }
    }

    private func seal(t: Double) -> some View {
        let flick = animated ? CGFloat(sin(t * 7) * 0.035 + sin(t * 11.3) * 0.02) : 0
        let sway = animated ? sin(t * 3.1) * 3 : 0
        return ZStack {
            RosetteShape()
                .fill(LinearGradient(colors: [Color(hex: 0xD4FF6A), Color.lime, Color(hex: 0x8FCB1E)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .rotationEffect(.degrees(animated ? t * 6 : 0))
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(Color.onLime)
                .scaleEffect(x: 1 - flick * 0.6, y: 1 + flick, anchor: .bottom)
                .rotationEffect(.degrees(sway), anchor: .bottom)
                .offset(y: size * 0.01)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Официальная отметка OXION")
    }
}

/// Большая анимированная отметка для окна: свечение, лучи, искры
struct OxionSealHero: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                // мягкое свечение
                Circle()
                    .fill(Color.lime.opacity(0.35 + 0.1 * sin(t * 2)))
                    .frame(width: 120, height: 120)
                    .blur(radius: 26)
                // лучи
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(Color.lime.opacity(0.22))
                        .frame(width: 3, height: 18)
                        .offset(y: -66)
                        .rotationEffect(.degrees(Double(i) * 30 + t * 14))
                }
                // искры
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) * .pi / 4 + t * 0.6
                    let r = 54 + 6 * sin(t * 3 + Double(i))
                    Image(systemName: "sparkle")
                        .font(.system(size: 9 + 3 * CGFloat(sin(t * 4 + Double(i)) + 1) / 2, weight: .bold))
                        .foregroundStyle(Color.lime.opacity(0.5 + 0.5 * sin(t * 4 + Double(i))))
                        .offset(x: cos(a) * r, y: sin(a) * r)
                }
                OxionSeal(size: 84, animated: true)
                    .shadow(color: Color.lime.opacity(0.6), radius: 14)
                    .scaleEffect(1 + 0.03 * sin(t * 2.2))
            }
            .frame(width: 150, height: 150)
        }
    }
}

/// Кнопка-отметка слева от имени: по нажатию — окно с пояснением
struct OxionSealButton: View {
    let official: OxOfficial
    let userId: Int
    let name: String
    let photo: String?
    var username: String? = nil
    var size: CGFloat = 22
    var animated = true
    @State private var show = false

    var body: some View {
        Button {
            show = true
            Haptic.tap(.soft)
        } label: { OxionSeal(size: size, animated: animated) }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) {
            OfficialSheet(official: official, userId: userId, name: name, photo: photo, username: username)
        }
    }
}

struct OfficialSheet: View {
    let official: OxOfficial
    let userId: Int
    let name: String
    let photo: String?
    var username: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            OxionSealHero()
                .padding(.top, 18)
            (Text(name).foregroundColor(Color.limeInk) + Text(" — ") + Text(official.headline))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Avatar(url: API.media(photo), name: name, size: 26)
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let t = official.title, !t.isEmpty {
                    Text("· " + t).font(.subheadline).foregroundStyle(Color.oxHint).lineLimit(1)
                }
            }
            .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: Capsule())
            Text(explain)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { dismiss() } label: {
                Text("Понятно").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime)
            .foregroundStyle(Color.onLime)
            Button {
                UIPasteboard.general.string = username.map { ProfileLink.string($0) } ?? AppSettings.serverURL.absoluteString + "/#u/\(userId)"
                Haptic.success()
                dismiss()
            } label: {
                Text("Копировать ссылку на профиль").font(.subheadline.weight(.semibold)).foregroundStyle(Color.limeInk)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 22)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
    }

    private var explain: String {
        var s = String(localized: "Огонёк OXION выдаётся только сотрудникам OXION и личным тренерам, которых OXION проверил: личность, документы и квалификацию. Купить или получить отметку другим способом нельзя.")
        if let since = official.since, since > 0 {
            let d = Date(timeIntervalSince1970: since / 1000).formatted(date: .long, time: .omitted)
            s += "\n\n" + String(localized: "Отметка выдана") + " " + d + "."
        }
        return s
    }
}

/// Сноска под профилем: «Этот аккаунт подтверждён…»
struct OfficialFootnote: View {
    let official: OxOfficial
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            OxionSeal(size: 16)
            Text(official.footnote)
                .font(.caption)
                .foregroundStyle(Color.oxHint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Меню владельца: выдать/снять отметку
struct OfficialAdminMenu: View {
    let userId: Int
    let current: OxOfficial?
    var onChange: (OxOfficial?) -> Void

    var body: some View {
        Menu {
            Section("Отметка OXION") {
                Button { Task { await set("staff") } } label: { Label("Сотрудник OXION", systemImage: "person.badge.shield.checkmark") }
                Button { Task { await set("trainer") } } label: { Label("Проверенный тренер", systemImage: "figure.strengthtraining.traditional") }
                Button { Task { await set("official") } } label: { Label("Официальный аккаунт", systemImage: "checkmark.seal") }
                if current != nil {
                    Button(role: .destructive) { Task { await remove() } } label: { Label("Снять отметку", systemImage: "xmark.seal") }
                }
            }
        } label: { OxionSeal(size: 24) }
    }

    private struct R: Decodable { let official: OxOfficial? }

    private func set(_ kind: String) async {
        do {
            let r: R = try await API.call("/official", method: "POST", body: ["user_id": userId, "kind": kind])
            Haptic.success()
            onChange(r.official)
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func remove() async {
        do {
            let _: R = try await API.call("/official", method: "DELETE", body: ["user_id": userId])
            Haptic.success()
            onChange(nil)
        } catch { OxAlert.error(error.localizedDescription) }
    }
}
