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
        switch key {
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
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size * 1.6, alignment: .top)
                    .offset(y: size * 0.18)
                    .clipped()
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
