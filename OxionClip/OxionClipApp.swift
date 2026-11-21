import SwiftUI
import StoreKit

// MARK: - OXION App Clip: мини-приложение без установки
// Открывается по QR-коду или NFC-метке в зале: …/clip/exercise/12, …/clip/trainer/34, …/clip/tag/<id>.
// Показывает упражнение с техникой, анкету тренера или клуб, и предлагает установить полный OXION.

let clipServer = "https://fit-app.brootai.workers.dev"

@main
struct OxionClipApp: App {
    @State private var target: ClipTarget?

    var body: some Scene {
        WindowGroup {
            ClipRootView(target: target)
                .preferredColorScheme(.dark)
                .tint(.lime)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
                    if let u = a.webpageURL { target = ClipTarget(url: u) }
                }
                .onOpenURL { u in target = ClipTarget(url: u) }
        }
    }
}

extension Color {
    static let lime = Color(red: 0.698, green: 0.933, blue: 0.216)
    static let oxBg = Color(red: 0.059, green: 0.063, blue: 0.071)
    static let oxCard = Color(red: 0.094, green: 0.098, blue: 0.11)
}

enum ClipTarget: Equatable {
    case exercise(Int), trainer(Int), tag(String)

    init?(url: URL) {
        let p = url.pathComponents.filter { $0 != "/" }
        guard let i = p.firstIndex(of: "clip"), p.count > i + 2 else { return nil }
        let kind = p[i + 1], v = p[i + 2]
        switch kind {
        case "exercise": if let n = Int(v) { self = .exercise(n) } else { return nil }
        case "trainer": if let n = Int(v) { self = .trainer(n) } else { return nil }
        case "tag": self = .tag(v)
        default: return nil
        }
    }

    var apiPath: String {
        switch self {
        case .exercise(let id): return "/api/public/exercise/\(id)"
        case .trainer(let id): return "/api/public/trainer/\(id)"
        case .tag(let id): return "/api/public/tag/\(id)"
        }
    }
}

/// Публичные данные (сервер отдаёт их без входа)
struct ClipItem: Decodable {
    let kind: String
    let name: String?
    let muscleName: String?
    let technique: String?
    let image: String?
    let city: String?
    let bio: String?
    let directions: [String]?
    let price: Double?
    let experience: Double?
    let rating: Double?
    let reviews: Int?
    let photo: String?
}

struct ClipRootView: View {
    let target: ClipTarget?
    @State private var item: ClipItem?
    @State private var errorText: String?
    @State private var install = false

    var body: some View {
        ZStack {
            Color.oxBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image("ox-logo").resizable().scaledToFit().frame(width: 22, height: 28)
                        Text("OXION").font(.headline.weight(.heavy))
                        Spacer()
                    }
                    if let item {
                        content(item)
                    } else if let errorText {
                        Text(errorText).foregroundStyle(.secondary)
                    } else if target == nil {
                        welcome
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { install = true } label: {
                Label("Установить OXION", systemImage: "arrow.down.app.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(.black)
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .appStoreOverlay(isPresented: $install) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
        .task(id: target) { await load() }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Тренировки, тренеры и прогресс").font(.title.bold())
            Text("Отсканируйте QR-код или поднесите iPhone к метке OXION в зале — здесь появится упражнение, тренер или ваш клуб.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ it: ClipItem) -> some View {
        switch it.kind {
        case "exercise":
            if let img = it.image, let u = URL(string: img.hasPrefix("http") ? img : clipServer + img) {
                AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.oxCard }
                    .frame(maxWidth: .infinity).frame(height: 240)
                    .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            Text(it.name ?? "Упражнение").font(.largeTitle.bold())
            if let m = it.muscleName, !m.isEmpty {
                Text(m).font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.lime.opacity(0.15), in: Capsule()).foregroundStyle(Color.lime)
            }
            if let t = it.technique, !t.isEmpty {
                Text("Техника").font(.headline)
                Text(t).foregroundStyle(.secondary)
            }
            Text("В полном OXION упражнение можно добавить в тренировку, а камера посчитает повторы.")
                .font(.footnote).foregroundStyle(.secondary)
        case "trainer":
            if let p = it.photo, let u = URL(string: p.hasPrefix("http") ? p : clipServer + p) {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.oxCard }
                    .frame(maxWidth: .infinity).frame(height: 300).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            Text(it.name ?? "Тренер").font(.largeTitle.bold())
            HStack(spacing: 8) {
                if let p = it.price { chip("\(Int(p)) ₽") }
                if let e = it.experience, e > 0 { chip("\(Int(e)) лет опыта") }
                if let r = it.rating, r > 0 { chip(String(format: "★ %.1f", r)) }
            }
            if let c = it.city { Label(c, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
            if let d = it.directions, !d.isEmpty { Text(d.joined(separator: " · ")).font(.subheadline) }
            if let b = it.bio, !b.isEmpty { Text(b).foregroundStyle(.secondary) }
            Text("Написать тренеру и записаться можно в полном OXION.").font(.footnote).foregroundStyle(.secondary)
        default:
            Image(systemName: "wave.3.right.circle.fill").font(.system(size: 54)).foregroundStyle(Color.lime)
            Text(it.name ?? "Клуб").font(.largeTitle.bold())
            if let c = it.city { Label(c, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
            Text("Это метка клуба OXION. Установите приложение и войдите — поднесите iPhone к метке, и посещение засчитается в вашу статистику.")
                .foregroundStyle(.secondary)
        }
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.oxCard, in: Capsule())
    }

    private func load() async {
        guard let target, let url = URL(string: clipServer + target.apiPath) else { return }
        item = nil
        errorText = nil
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
                errorText = "Не нашли: возможно, анкета скрыта или метка выключена."
                return
            }
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            item = try dec.decode(ClipItem.self, from: data)
        } catch {
            errorText = "Нет соединения. Проверьте интернет."
        }
    }
}
