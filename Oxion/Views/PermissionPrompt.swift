import SwiftUI
import ActivityKit

// MARK: - Окна-подсказки с картинкой (как в TikTok): мини-iPhone показывает,
// где в «Настройках → Oxion» нужный переключатель, он обведён лаймовым пунктиром.

struct SettingsArt {
    struct Row: Hashable {
        let icon: String
        let tint: Color
        let title: String
        var value: String? = nil      // «Нет», «Ограниченный доступ»…
        var toggle: Bool = false      // строка с переключателем
    }
    let highlight: Row
    var others: [Row] = []
}

/// Карточка окна: картинка сверху, заголовок и текст слева, две кнопки рядом
struct PromptCard: View {
    let a: OxAlertData
    let art: SettingsArt
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                PhoneMock(art: art)
                    .padding(.top, 18)
            }
            .frame(height: 178)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(a.title)
                .font(.title3.bold())
                .padding(.horizontal, 6)
            if !a.message.isEmpty {
                Text(a.message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            HStack(spacing: 10) {
                ForEach(a.buttons) { b in
                    Button {
                        dismiss()
                        b.action?()
                    } label: {
                        Text(b.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(b.role == .primary ? Color.lime : Color.white.opacity(0.16))
                    .foregroundStyle(b.role == .primary ? Color.black : Color.white)
                    .controlSize(.large)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
    }
}

/// Нарисованный iPhone с экраном «Настройки → Oxion»
struct PhoneMock: View {
    let art: SettingsArt
    @State private var pulse = false
    @State private var on = false

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color(white: 0.35), lineWidth: 3))
            VStack(alignment: .leading, spacing: 8) {
                // строка состояния и остров
                HStack {
                    Text("9:41").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Capsule().fill(.black).frame(width: 58, height: 17)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.75percent")
                    }
                    .font(.system(size: 9, weight: .semibold))
                }
                .padding(.top, 9)
                // шапка настроек
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20).background(Color.white.opacity(0.1), in: Circle())
                    Spacer()
                    HStack(spacing: 4) {
                        Image("ox-logo").resizable().scaledToFit().frame(width: 9, height: 12)
                        Text("Oxion").font(.system(size: 12, weight: .bold))
                    }
                    Spacer()
                    Color.clear.frame(width: 20, height: 20)
                }
                Text("Разрешите Oxion доступ").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                VStack(spacing: 0) {
                    row(art.highlight, highlighted: true)
                    ForEach(art.others.prefix(2), id: \.self) { r in
                        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 30)
                        row(r, highlighted: false)
                    }
                }
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
        }
        .frame(width: 236, height: 220)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.spring(duration: 0.4)) { on = true }
            }
        }
    }

    private func row(_ r: SettingsArt.Row, highlighted: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: r.icon)
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(r.tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(r.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if r.toggle {
                Capsule().fill(highlighted && on ? Color.lime : Color.white.opacity(0.22))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: highlighted && on ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    }
                    .padding(4)
                    .overlay {
                        if highlighted { dashed(Capsule()) }
                    }
            } else if let v = r.value {
                HStack(spacing: 2) {
                    Text(highlighted && on ? "Разрешить" : v).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(highlighted && on ? Color.lime : .white.opacity(0.55))
                        .contentTransition(.opacity)
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay {
                    if highlighted { dashed(Capsule()) }
                }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
    }

    private func dashed<S: Shape>(_ s: S) -> some View {
        s.stroke(Color.lime, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            .scaleEffect(pulse ? 1.06 : 0.98)
            .shadow(color: Color.lime.opacity(0.7), radius: pulse ? 5 : 1)
    }
}

// MARK: - Картинки для каждого доступа

extension PermKind {
    var settingsRow: SettingsArt.Row {
        switch self {
        case .notifications: return .init(icon: icon, tint: tint, title: title, value: "Выкл.")
        case .location: return .init(icon: icon, tint: tint, title: title, value: "Никогда")
        case .contacts: return .init(icon: icon, tint: tint, title: title, value: "Нет доступа")
        case .photos: return .init(icon: icon, tint: tint, title: title, value: "Нет")
        case .faceID: return .init(icon: icon, tint: tint, title: "Face ID", toggle: true)
        case .liveActivities: return .init(icon: icon, tint: tint, title: title, toggle: true)
        default: return .init(icon: icon, tint: tint, title: title, toggle: true)
        }
    }

    var art: SettingsArt {
        let all: [PermKind] = [.notifications, .location, .contacts, .photos, .camera, .microphone, .liveActivities]
        return SettingsArt(highlight: settingsRow, others: all.filter { $0 != self }.prefix(2).map { $0.settingsRowDim })
    }

    private var settingsRowDim: SettingsArt.Row {
        var r = settingsRow
        if r.value != nil { r.value = "Разрешено" }
        return r
    }

    /// Текст окна: до первого запроса и когда доступ уже запрещён
    func promptText(denied: Bool) -> (title: String, message: String) {
        let what: String
        switch self {
        case .notifications: what = "присылать сообщения от тренера, напоминания о тренировках и сигнал «отдых окончен»"
        case .location: what = "определить ваш город и показать тренеров рядом"
        case .contacts: what = "найти ваших знакомых, чтобы пригласить их в OXION. Контакты остаются на телефоне"
        case .photos: what = "сохранять карточки прогресса и итогов тренировки в «Фото»"
        case .camera: what = "считать повторы по камере, снимать фото прогресса и звонить по видео"
        case .microphone: what = "записывать голосовые, кружки и звонить"
        case .faceID: what = "закрывать ваши фото прогресса"
        case .localNetwork: what = "находить Apple TV и тренажёры в вашей сети Wi‑Fi"
        case .backgroundRefresh: what = "обновлять виджеты и счётчик сообщений, пока OXION закрыт"
        case .cellular: what = "работать без Wi‑Fi"
        case .liveActivities: what = "показывать тренировку и синхронизацию в Dynamic Island и на экране блокировки"
        }
        let t = denied ? "Включите «\(title)»" : title
        let m = denied
            ? "Чтобы OXION мог \(what), разрешите доступ в настройках устройства."
            : "Чтобы OXION мог \(what), разрешите доступ в следующем окне."
        return (t, m)
    }
}

enum PermPrompt {
    /// Показать окно с картинкой. До запроса — «Продолжить» запускает системный запрос;
    /// если доступ запрещён — «Открыть настройки».
    @MainActor
    static func show(_ k: PermKind, denied: Bool, onContinue: (() -> Void)? = nil) {
        let t = k.promptText(denied: denied)
        let primary = denied
            ? OxAlertButton(title: "Открыть настройки", role: .primary) { PermissionCenter.shared.openSettings(k) }
            : OxAlertButton(title: "Продолжить", role: .primary) { onContinue?() }
        AlertCenter.shared.show(OxAlertData(icon: k.icon, tint: .lime, title: t.title, message: t.message,
                                            buttons: [OxAlertButton(title: denied ? "Не разрешать" : "Не сейчас", role: .cancel), primary],
                                            art: k.art))
    }
}
