import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

extension Notification.Name {
    static let oxionShake = Notification.Name("oxionShake")
}

/// Встряхивание телефона в любом месте приложения → визитка с QR (как в PWA).
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .oxionShake, object: nil)
        }
    }
}

enum QR {
    static func image(_ text: String, scale: CGFloat = 12) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct QRView: View {
    let text: String

    var body: some View {
        if let img = QR.image(text) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 120))
        }
    }
}

/// Визитка: QR на профиль, у тренера — ещё «Пригласить клиента»
struct MyCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private var isTrainer: Bool { model.me?.mode == "trainer" || model.me?.role == "trainer" }

    private func link(_ param: String, start: Bool = false) -> String {
        let id = model.me?.id ?? 0
        if let b = model.meta?.botUsername, !b.isEmpty {
            return "https://t.me/\(b.replacingOccurrences(of: "@", with: ""))?\(start ? "start" : "startapp")=\(param)"
        }
        return AppSettings.serverURL.absoluteString + "/#" + (param.hasPrefix("t") ? "trainer/\(id)" : param.hasPrefix("coach") ? "coachjoin/\(id)" : "u/\(id)")
    }

    private var subtitle: String {
        let city = model.me?.city ?? ""
        if isTrainer { return city.isEmpty ? "Тренер" : "Тренер · " + city }
        return city.isEmpty ? "Oxion" : city
    }

    private var current: String {
        let id = model.me?.id ?? 0
        if tab == 1 { return link("coach\(id)", start: true) }
        return isTrainer ? link("t\(id)") : link("u\(id)")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Avatar(url: API.media(model.me?.photoUrl), name: model.me?.displayName ?? "?", size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.me?.displayName ?? "Я").font(.title3.bold())
                        Text(subtitle)
                            .foregroundStyle(Color.oxHint)
                    }
                    Spacer()
                }
                if isTrainer {
                    Picker("", selection: $tab) {
                        Text("Визитка").tag(0)
                        Text("Пригласить клиента").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                QRView(text: current)
                    .frame(maxWidth: 280)
                    .shadow(color: Color.lime.opacity(0.35), radius: 24)
                Text(tab == 1 ? "Клиент наведёт камеру — и сразу подключится к вам: вы увидите его дневник, сможете ставить цели и назначать тренировки."
                     : "Покажите QR — человек откроет ваш профиль в Oxion.")
                    .font(.subheadline)
                    .foregroundStyle(Color.oxHint)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    ShareLink(item: current) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    Button {
                        UIPasteboard.general.string = current
                        Haptic.success()
                    } label: {
                        Label("Копировать", systemImage: "doc.on.doc")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                Text("Встряхните телефон в любом месте приложения, чтобы открыть это окно.")
                    .font(.caption)
                    .foregroundStyle(Color.oxHint)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(isTrainer ? "Моя визитка" : "Мой профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Картинки групп мышц (из PWA: m-chest, m-back …)

enum MuscleArt {
    /// имя картинки в ассетах для ключа группы мышц
    static func image(_ key: String?) -> String? {
        switch key {
        case "chest": return "m-chest"
        case "back": return "m-back"
        case "shoulders": return "m-shoulders"
        case "biceps", "triceps", "arms": return "m-arms"
        case "abs": return "m-abs"
        case "legs", "glutes": return "m-legs"
        default: return nil
        }
    }

    static func symbol(_ key: String?) -> String {
        switch key {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "shoulders": return "figure.arms.open"
        case "biceps", "triceps", "arms": return "dumbbell.fill"
        case "legs": return "figure.step.training"
        case "glutes": return "figure.cross.training"
        case "abs": return "figure.core.training"
        case "cardio": return "heart.fill"
        default: return "figure.mixed.cardio"
        }
    }

    static func emoji(_ key: String?) -> String {
        switch key {
        case "chest": return "🏋️"
        case "back": return "🧗"
        case "shoulders": return "🤸"
        case "biceps": return "💪"
        case "triceps": return "🦾"
        case "legs": return "🦵"
        case "glutes": return "🍑"
        case "abs": return "⚡"
        case "cardio": return "❤️"
        default: return "🔥"
        }
    }
}

/// Фигура с подсвеченной группой мышц, а для групп без картинки — значок
struct MuscleFigure: View {
    let key: String?
    var height: CGFloat = 120

    var body: some View {
        if let name = MuscleArt.image(key) {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(height: height)
        } else {
            Text(MuscleArt.emoji(key))
                .font(.system(size: height * 0.35))
                .frame(height: height)
        }
    }
}

/// Миниатюра для списков (упражнения, тренировки): фигура мышц в скруглённой плашке
struct MuscleThumb: View {
    let key: String?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color.lime.opacity(0.22), Color.oxCard2], startPoint: .bottom, endPoint: .top))
            if let name = MuscleArt.image(key) {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size * 1.6, alignment: .top)
                    .offset(y: size * 0.18)
                    .clipped()
            } else {
                Image(systemName: MuscleArt.symbol(key))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.lime)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
