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

// MARK: - Картинки групп мышц (из PWA: m-chest, m-back …)

enum MuscleArt {
    /// бег, пробежка, спринт — бегущий человек вместо общей кардио-картинки
    static func image(_ key: String?, name: String?) -> String? {
        let n = (name ?? "").lowercased()
        if ["бег", "пробеж", "спринт", "run", "jog", "sprint"].contains(where: { n.contains($0) }) && !n.contains("на месте") {
            return "runner"
        }
        return image(key)
    }

    /// имя картинки в ассетах для ключа группы мышц
    static func image(_ key: String?) -> String? {
        switch group(key) {
        case "chest": return "m-chest"
        case "back": return "m-back"
        case "shoulders": return "m-shoulders"
        case "biceps", "triceps", "arms": return "m-arms"
        case "abs": return "m-abs"
        case "legs": return "m-legs"
        case "glutes": return "m-glutes"
        case "cardio": return "cardio-man"
        case "run": return "runner"
        default: return nil
        }
    }

    /// Подробные мышцы (из 3D-модели) → общая группа: quads → legs, glute_max → glutes …
    static func group(_ key: String?) -> String? {
        guard let k = key?.lowercased() else { return nil }
        switch k {
        case "quads", "hamstrings", "calves", "soleus", "adductors", "abductors", "legs": return "legs"
        case "glute_max", "glute_med", "glutes": return "glutes"
        case "lats", "traps", "rhomboids", "lower_back", "erectors", "back": return "back"
        case "abs_rectus", "obliques", "abs": return "abs"
        case "delt_front", "delt_mid", "delt_rear", "shoulders": return "shoulders"
        case "pecs", "pec_major", "pec_upper", "chest": return "chest"
        case "forearms", "biceps", "triceps", "arms": return k == "forearms" ? "arms" : k
        default: return k
        }
    }

    /// Где на картинке подсвечена группа (доля высоты) и насколько уменьшить картинку,
    /// чтобы в маленькой плашке была видна именно она, а не голова и грудь
    static func focus(_ key: String?) -> (y: CGFloat, zoom: CGFloat) {
        switch group(key) {
        case "legs": return (0.70, 0.78)       // бёдра и голени
        case "glutes": return (0.51, 0.95)     // ягодицы со спины
        case "back": return (0.36, 0.95)
        case "abs": return (0.33, 1.0)
        default: return (0.25, 1.0)            // грудь, плечи, руки
        }
    }

    /// Бег/ходьба/кардио — фигура целиком
    static func isWholeFigure(_ image: String) -> Bool { image == "runner" || image == "cardio-man" }

    static func symbol(_ key: String?) -> String {
        switch group(key) {
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
        switch group(key) {
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
    var name: String? = nil

    var body: some View {
        if let name = MuscleArt.image(key, name: self.name) {
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
    var name: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color.lime.opacity(0.22), Color.oxCard2], startPoint: .bottom, endPoint: .top))
            if let name = MuscleArt.image(key, name: self.name) {
                if MuscleArt.isWholeFigure(name) {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size * 1.6, alignment: .top)
                        .offset(y: size * 0.18)
                        .clipped()
                } else {
                    // наводим «камеру» на подсвеченную группу: ноги и ягодицы больше не прячутся внизу
                    let f = MuscleArt.focus(key)
                    let ui = UIImage(named: name)
                    let ratio = ui.map { $0.size.height / max($0.size.width, 1) } ?? 2.73
                    let w = size * f.zoom
                    let h = w * ratio
                    let raw = h * (0.5 - f.y)
                    let limit = max(0, (h - size) / 2)      // не показываем пустоту за краем картинки
                    Image(name)
                        .resizable()
                        .frame(width: w, height: h)
                        .offset(y: min(limit, max(-limit, raw)))
                }
            } else {
                Image(systemName: MuscleArt.symbol(key))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.limeInk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}


/// Миниатюра тренировки с несколькими группами: главная группа + маленький значок второй («Спина и ноги»)
struct MuscleStackThumb: View {
    let keys: [String]
    var size: CGFloat = 52
    var name: String? = nil

    var body: some View {
        let uniq = keys.reduce(into: [String]()) { acc, k in
            let g = MuscleArt.group(k) ?? k
            if !acc.contains(where: { (MuscleArt.group($0) ?? $0) == g }) { acc.append(k) }
        }
        ZStack(alignment: .bottomTrailing) {
            MuscleThumb(key: uniq.first, size: size, name: name)
            if uniq.count > 1 {
                MuscleThumb(key: uniq[1], size: size * 0.5)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.6), lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        if uniq.count > 2 {
                            Text("+\(uniq.count - 2)")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color.onLime)
                                .padding(.horizontal, 3)
                                .background(Color.lime, in: Capsule())
                                .offset(x: 4, y: -4)
                        }
                    }
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: size, height: size)
    }
}
