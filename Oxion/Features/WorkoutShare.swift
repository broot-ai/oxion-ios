import SwiftUI

// «Поделиться результатом тренировки»: красивая карточка-картинка через системное меню «Поделиться»
// (Сообщения, Telegram, Instagram Stories, сохранить в Фото и т.д.).

struct WorkoutResultCard: View {
    let title: String
    let date: Date
    let duration: String
    let sets: Int
    let volume: Int
    let lines: [(String, String)]   // упражнение — «3 × 10 × 60 кг»

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image("ox-logo").resizable().scaledToFit().frame(height: 34)
                Text("OXION").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                Spacer()
                Text(date.formatted(.dateTime.day().month(.wide))).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ТРЕНИРОВКА ЗАВЕРШЕНА").font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(Color.lime)
                Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(.white).lineLimit(2)
            }
            HStack(spacing: 10) {
                tile(duration, "время")
                tile("\(sets)", "подходов")
                tile(volume > 0 ? "\(volume)" : "—", "кг объём")
            }
            if !lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { i, l in
                        HStack {
                            Text(l.0).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(l.1).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.vertical, 9)
                        if i < min(lines.count, 6) - 1 { Divider().overlay(Color.white.opacity(0.12)) }
                    }
                    if lines.count > 6 {
                        Text("и ещё \(lines.count - 6)").font(.caption).foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            Text("Тренируюсь в OXION").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(26)
        .frame(width: 380)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x15200C), Color(hex: 0x0B0C0E), .black], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.lime.opacity(0.25), .clear], center: .topTrailing, startRadius: 10, endRadius: 320)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func tile(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 24, weight: .bold).monospacedDigit()).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            Text(t).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    func render() -> Image? {
        let r = ImageRenderer(content: self.padding(10).background(Color.black))
        r.scale = 3
        guard let ui = r.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

/// Кнопка «Поделиться результатом»
struct ShareWorkoutButton: View {
    let card: WorkoutResultCard
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, message: Text("Закрыл тренировку в OXION 💪"),
                          preview: SharePreview(card.title, image: image)) {
                    Label("Поделиться результатом", systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .simultaneousGesture(TapGesture().onEnded { OxSound.play(.tap) })
            } else {
                ProgressView().frame(height: 44)
            }
        }
        .task { image = card.render() }
    }
}
