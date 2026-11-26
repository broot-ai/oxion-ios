import SwiftUI
import UIKit
import MapKit
import CoreLocation
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Интерактивные наклейки историй (как в Telegram): ссылка, геопозиция, погода, звук, реакция

/// Звук к истории: локальный файл + выбранный кусок
struct StoryAudio: Equatable {
    var url: URL
    var title: String
    var artist: String
    var duration: Double
    var start: Double = 0
    var length: Double { min(15, max(1, duration - start)) }
}

/// Наклейка-«плашка»: ссылка / геопозиция. variant: 0 — белая, 1 — тёмная, 2 — прозрачная
struct StoryChip: View {
    let icon: String
    let text: String
    var variant = 0

    var body: some View {
        let fg: Color = variant == 0 ? .black : .white
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .bold))
            Text(text.uppercased())
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(variant == 0 ? Color.white : (variant == 1 ? Color.black.opacity(0.55) : Color.white.opacity(0.18)))
        }
        .overlay {
            if variant == 2 { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 2) }
        }
        .shadow(color: .black.opacity(variant == 0 ? 0.2 : 0), radius: 6, y: 2)
    }
}

enum StoryWeather {
    static func icon(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "☀️" : "🌙"
        case 1, 2: return day ? "🌤️" : "☁️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51...67: return "🌧️"
        case 71...77, 85, 86: return "❄️"
        case 80...82: return "🌦️"
        case 95...99: return "⛈️"
        default: return "🌡️"
        }
    }
    static func text(_ t: Int) -> String { "\(t)°C" }

    /// текущая погода по геопозиции (через наш сервер, Open-Meteo)
    @MainActor static func fetch() async -> (temp: Int, code: Int, day: Bool)? {
        let loc = OneShotLocation()
        loc.request()
        for _ in 0..<40 where loc.coord == nil { try? await Task.sleep(for: .milliseconds(150)) }
        guard let c = loc.coord else { return nil }
        struct R: Decodable { let temp: Int; let code: Int; let day: Bool? }
        guard let r: R = try? await API.call("/weather", query: ["lat": String(c.latitude), "lon": String(c.longitude)]) else { return nil }
        return (r.temp, r.code, r.day ?? true)
    }
}

struct StoryWeatherChip: View {
    let temp: Int
    let code: Int
    let day: Bool
    var variant = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(StoryWeather.icon(code, day: day)).font(.system(size: 30))
            Text(StoryWeather.text(temp)).font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(variant == 0 ? Color.white : (variant == 1 ? Color.black : Color.white))
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(variant == 0 ? Color.black.opacity(0.35) : (variant == 1 ? Color.white : Color.clear))
        }
        .shadow(color: .black.opacity(variant == 2 ? 0.5 : 0), radius: 4)
    }
}

/// Реакция: эмодзи в белом пузыре. Зритель нажимает — ставит лайк истории
struct StoryReactionBubble: View {
    let emoji: String
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.white).frame(width: 110, height: 110)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            Circle().fill(.white).frame(width: 18, height: 18).offset(x: 4, y: 4)
            Circle().fill(.white).frame(width: 9, height: 9).offset(x: 16, y: 16)
            Text(emoji).font(.system(size: 62)).frame(width: 110, height: 110)
        }
        .frame(width: 128, height: 128)
    }
}

struct StoryReactionPicker: View {
    var onPick: (String) -> Void
    private let list = ["❤️", "🔥", "👍", "🤣", "🥰", "💪", "😍", "👏", "😮", "🗿"]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(list, id: \.self) { e in
                Button { onPick(e); Haptic.tap(.soft) } label: { Text(e).font(.system(size: 26)) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Маркеры «как настоящие» (панель рисования)

struct StoryPenTool: View {
    let tool: StoryTool
    let color: Color
    let width: CGFloat

    var body: some View {
        let bodyGrad = LinearGradient(colors: [Color(white: 0.16), Color(white: 0.27), Color(white: 0.14)], startPoint: .leading, endPoint: .trailing)
        VStack(spacing: 0) {
            tip
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4).fill(bodyGrad).frame(width: 30, height: 70)
                band
            }
        }
        .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder private var tip: some View {
        switch tool {
        case .pen:
            ZStack(alignment: .top) {
                PenCone().fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.3), Color(white: 0.12)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 30, height: 40)
                PenCone().fill(color).frame(width: 8, height: 11)
            }
        case .arrow:
            VStack(spacing: 1) {
                Image(systemName: "arrow.up").font(.system(size: 20, weight: .black)).foregroundStyle(color)
                RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 30, height: 12)
            }
        case .marker:
            ZStack(alignment: .bottom) {
                ChiselTip().fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.28)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 22, height: 28)
                ChiselTip().fill(color.opacity(0.9)).frame(width: 22, height: 8).offset(y: -20)
            }
            .padding(.top, 2)
        case .liner:
            VStack(spacing: 0) {
                Capsule().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: color, radius: 6)
                    .shadow(color: color, radius: 3)
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.2)).frame(width: 20, height: 18)
            }
        case .eraser:
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                .fill(Color(red: 0.89, green: 0.62, blue: 0.62))
                .frame(width: 30, height: 26)
        default:
            PenCone().fill(color).frame(width: 30, height: 40)
        }
    }

    @ViewBuilder private var band: some View {
        switch tool {
        case .pen, .arrow: Rectangle().fill(color).frame(width: 30, height: 4).padding(.top, 8)
        case .liner: Rectangle().fill(Color(white: 0.6)).frame(width: 30, height: 4).padding(.top, 14)
        default: EmptyView()
        }
    }
}

private struct PenCone: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - r.width * 0.08, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.08, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct ChiselTip: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.35))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Полоса выбора куска трека (внизу холста)

struct StoryTrimBar: View {
    let audio: StoryAudio
    var onChange: (Double) -> Void
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { g in
            let W = g.size.width
            let total = max(audio.duration, 1)
            let win = W * min(1, 15 / total)
            let x = W * audio.start / total
            ZStack(alignment: .leading) {
                // «волна»
                HStack(spacing: 2) {
                    ForEach(0..<70, id: \.self) { i in
                        Capsule().fill(.white.opacity(0.45))
                            .frame(width: 2, height: 6 + CGFloat((i * 37 + 11) % 19))
                    }
                }
                .frame(width: W, height: 40)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white, lineWidth: 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                    .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 5, height: 22).offset(x: 4) }
                    .overlay(alignment: .trailing) { Capsule().fill(.white).frame(width: 5, height: 22).offset(x: -4) }
                    .frame(width: win, height: 40)
                    .offset(x: x)
                    .gesture(DragGesture()
                        .onChanged { v in
                            if dragStart == nil { dragStart = audio.start }
                            let s = (dragStart ?? 0) + Double(v.translation.width / W) * total
                            onChange(min(max(0, s), max(0, total - 15)))
                        }
                        .onEnded { _ in dragStart = nil })
            }
        }
        .frame(height: 40)
        .overlay(alignment: .topLeading) {
            Label("\(audio.artist.isEmpty ? "" : audio.artist + " — ")\(audio.title)", systemImage: "music.note")
                .font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                .offset(y: -20)
        }
    }
}

// MARK: - Лист наклеек: поиск, кнопки «Ссылка/Геопозиция/Погода/Звук/Реакция», эмодзи, фото, фигуры

struct StoryStickerSheet: View {
    var onPick: (StoryOverlay) -> Void
    var onLink: () -> Void
    var onGeo: () -> Void
    var onSound: () -> Void
    var onResults: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 1
    @State private var query = ""
    @State private var photo: PhotosPickerItem?
    @State private var weather: (temp: Int, code: Int, day: Bool)?
    @State private var weatherLoading = true

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск", text: $query).textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .padding(.horizontal, 16).padding(.top, 18)

            ScrollView {
                VStack(spacing: 14) {
                    if query.isEmpty {
                        // интерактивные наклейки
                        FlowLayoutSimple(spacing: 10) {
                            chip("chart.bar.xaxis", "РЕЗУЛЬТАТЫ") { dismiss(); after { onResults() } }
                            chip("link", "ССЫЛКА") { dismiss(); after { onLink() } }
                            chip("mappin.and.ellipse", "ГЕОПОЗИЦИЯ") { dismiss(); after { onGeo() } }
                            Button {
                                guard let w = weather else { return }
                                var o = StoryOverlay(kind: .weather); o.temp = w.temp; o.wcode = w.code; o.day = w.day
                                o.center = CGPoint(x: 0.5, y: 0.3)
                                onPick(o); dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    if let w = weather { Text(StoryWeather.icon(w.code, day: w.day)); Text(StoryWeather.text(w.temp)) }
                                    else if weatherLoading { ProgressView().controlSize(.small); Text("ПОГОДА") }
                                    else { Image(systemName: "thermometer.medium"); Text("ПОГОДА") }
                                }
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 12).frame(height: 38)
                                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            chip("music.note", "ЗВУК") { dismiss(); after { onSound() } }
                            Button {
                                var o = StoryOverlay(kind: .reaction); o.emoji = "❤️"
                                onPick(o); dismiss()
                            } label: { StoryReactionBubble(emoji: "❤️").scaleEffect(0.36).frame(width: 46, height: 46) }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                    }
                    switch tab {
                    case 0:
                        PhotosPicker(selection: $photo, matching: .images) {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 40)).foregroundStyle(StoryEditorView.blue)
                                Text("Фото из галереи").font(.headline)
                                Text("Ляжет поверх истории — двигайте, увеличивайте, поворачивайте")
                                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(28)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                    case 2:
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                            ForEach(StoryShapeKind.allCases) { s in
                                ForEach([Color.white, Color.lime, Color(hex: 0xF2584D)], id: \.self) { c in
                                    Button {
                                        var o = StoryOverlay(kind: .shape); o.shape = s; o.color = c
                                        onPick(o); dismiss()
                                    } label: { StoryShapeView(kind: s, color: c).scaleEffect(0.42).frame(height: 70) }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    default:
                        emojiGrid
                    }
                }
                .padding(.bottom, 70)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                tabButton(0, icon: "photo")
                tabButton(1, title: "Эмодзи")
                tabButton(2, title: "Фигуры")
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 10)
        }
        .task {
            weather = await StoryWeather.fetch()
            weatherLoading = false
        }
        .onChange(of: photo) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), let i = UIImage(data: d) {
                    var o = StoryOverlay(kind: .image); o.image = i.oxResized(maxSide: 900)
                    onPick(o); dismiss()
                }
            }
        }
    }

    private func after(_ f: @escaping () -> Void) {
        Task { try? await Task.sleep(for: .milliseconds(450)); f() }
    }

    private func chip(_ icon: String, _ t: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
                Text(t).font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tabButton(_ i: Int, icon: String? = nil, title: String? = nil) -> some View {
        Button { withAnimation(.smooth(duration: 0.2)) { tab = i } } label: {
            Group {
                if let icon { Image(systemName: icon) } else { Text(title ?? "") }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).frame(height: 34)
            .background(tab == i ? Color.primary.opacity(0.15) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // все эмодзи по категориям + поиск (русские слова и английские названия Юникода)
    private var emojiGrid: some View {
        let list = StoryEmoji.search(query)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, e in
                Button {
                    var o = StoryOverlay(kind: .emoji); o.emoji = e
                    onPick(o); dismiss()
                } label: { Text(e).font(.system(size: 34)) }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }
}

enum StoryEmoji {
    /// сначала «спортивные», потом все эмодзи Юникода
    static let all: [String] = {
        let top = ["🔥", "💪", "🏋️", "🏃", "🥇", "🏆", "⚡️", "✅", "❤️", "😍", "😂", "😎", "🤯", "🥵", "🙌", "👏", "💯", "🎯", "🚀", "⭐️"]
        var out = top
        var seen = Set(top)
        let ranges: [ClosedRange<UInt32>] = [0x1F600...0x1F64F, 0x1F910...0x1F9FF, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF, 0x2600...0x27BF, 0x1FA70...0x1FAFF]
        for r in ranges {
            for v in r {
                guard let sc = Unicode.Scalar(v), sc.properties.isEmojiPresentation else { continue }
                let s = String(sc)
                if seen.insert(s).inserted { out.append(s) }
            }
        }
        return out
    }()

    private static let ru: [String: [String]] = [
        "сердц": ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "💖"], "огон": ["🔥"], "сил": ["💪"], "спорт": ["🏋️", "🏃", "🚴", "🏊", "⛹️", "🤸", "🥊"],
        "смех": ["😂", "🤣", "😆"], "любов": ["😍", "🥰", "❤️", "😘"], "плач": ["😭", "😢"], "злой": ["😡", "🤬", "😤"], "кот": ["🐱", "😺", "🐈"],
        "собак": ["🐶", "🐕"], "еда": ["🍕", "🍔", "🥗", "🍗", "🥑", "🍎"], "кофе": ["☕️"], "солн": ["☀️", "🌞"], "звезд": ["⭐️", "🌟", "✨"],
        "побед": ["🏆", "🥇", "✌️"], "класс": ["👍", "👌", "🔥"], "ок": ["👌", "✅"], "сон": ["😴", "💤"], "вода": ["💧", "🥤"]
    ]

    static func search(_ q: String) -> [String] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return all }
        var res: [String] = []
        for (k, v) in ru where k.hasPrefix(s) || s.hasPrefix(k) { res += v }
        for e in all {
            let name = e.unicodeScalars.compactMap { $0.properties.name?.lowercased() }.joined(separator: " ")
            if name.contains(s) { res.append(e) }
        }
        var seen = Set<String>()
        return res.filter { seen.insert($0).inserted }
    }
}

// MARK: - Создание ссылки

struct StoryLinkSheet: View {
    var onDone: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @FocusState private var focus: Bool

    private var valid: String? {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard u.count > 3, u.contains(".") else { return nil }
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        return URL(string: u)?.host() != nil ? u : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("URL-адрес") {
                    TextField("https://example.com", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus)
                }
                Section("Отображаемый текст (необязательно)") {
                    TextField("Текст ссылки", text: $title)
                }
            }
            .navigationTitle("Создание ссылки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let u = valid else { return }
                        onDone(u, title.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                    .disabled(valid == nil)
                }
            }
            .onAppear { focus = true }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Геопозиция: карта + поиск мест

struct StoryGeoSheet: View {
    var onDone: (String, Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var title = ""
    @State private var subtitle = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var geocodeTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $camera) { UserAnnotation() }
                    .mapControls { MapUserLocationButton() }
                    .onMapCameraChange(frequency: .onEnd) { ctx in
                        center = ctx.region.center
                        geocode(ctx.region.center)
                    }
                    .overlay {
                        Image(systemName: "mappin")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(StoryEditorView.blue)
                            .offset(y: -17)
                            .allowsHitTesting(false)
                    }
                VStack(spacing: 0) {
                    if !results.isEmpty {
                        List(results, id: \.self) { it in
                            Button {
                                let c = it.placemark.coordinate
                                onDone(it.name ?? "Место", c.latitude, c.longitude)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.name ?? "").font(.subheadline.weight(.semibold))
                                    if let a = it.placemark.title { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 260)
                    }
                    Button {
                        guard let c = center else { return }
                        onDone(title.isEmpty ? "Здесь" : title, c.latitude, c.longitude)
                        dismiss()
                    } label: {
                        VStack(spacing: 2) {
                            Text("Отправить геопозицию").font(.headline)
                            if !subtitle.isEmpty { Text(subtitle).font(.caption).opacity(0.8).lineLimit(1) }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(StoryEditorView.blue, in: Capsule())
                    }
                    .padding(16)
                    .disabled(center == nil)
                }
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Геопозиция")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Поиск мест")
            .onSubmit(of: .search) { search() }
            .onChange(of: query) { if query.isEmpty { results = [] } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        }
    }

    private func search() {
        let r = MKLocalSearch.Request()
        r.naturalLanguageQuery = query
        if let c = center { r.region = MKCoordinateRegion(center: c, latitudinalMeters: 20000, longitudinalMeters: 20000) }
        Task {
            if let res = try? await MKLocalSearch(request: r).start() { results = Array(res.mapItems.prefix(12)) }
        }
    }

    private func geocode(_ c: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  let pm = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first else { return }
            title = pm.locality ?? pm.name ?? ""
            subtitle = [pm.thoroughfare, pm.subThoroughfare, pm.locality].compactMap { $0 }.joined(separator: ", ")
        }
    }
}

// MARK: - Звук: из файлов или поиск музыки

struct StorySoundSheet: View {
    var onPick: (StoryAudio) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var files = false
    @State private var music = false
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { files = true } label: { Label("Выбрать из файлов", systemImage: "icloud") }
                    Button { music = true } label: { Label("Найти песню", systemImage: "magnifyingglass") }
                }
                Section {
                    Text("Выбранный трек можно сдвигать по полосе внизу истории — в историю попадёт 15 секунд.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Звук")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
            .overlay { if loading { ProgressView("Загружаем трек…").padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .fileImporter(isPresented: $files, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav]) { r in
                guard case .success(let u) = r else { return }
                Task { await useFile(u, title: u.deletingPathExtension().lastPathComponent, artist: "", secured: true) }
            }
            .sheet(isPresented: $music) {
                MusicPickerSheet { m in
                    guard let p = m.preview, let u = URL(string: p) else { OxAlert.error("У этого трека нет отрывка"); return }
                    Task { await download(u, title: m.title, artist: m.artist ?? "") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func download(_ u: URL, title: String, artist: String) async {
        loading = true
        defer { loading = false }
        guard let (tmp, _) = try? await URLSession.shared.download(from: u) else { OxAlert.error("Не удалось загрузить трек"); return }
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("story-audio-\(UUID().uuidString).m4a")
        try? FileManager.default.moveItem(at: tmp, to: dst)
        await useFile(dst, title: title, artist: artist, secured: false)
    }

    private func useFile(_ u: URL, title: String, artist: String, secured: Bool) async {
        var local = u
        if secured {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("story-audio-\(UUID().uuidString).\(u.pathExtension.isEmpty ? "m4a" : u.pathExtension)")
            do { try FileManager.default.copyItem(at: u, to: dst) } catch { OxAlert.error("Не удалось открыть файл"); return }
            local = dst
        }
        let d = (try? await AVURLAsset(url: local).load(.duration).seconds) ?? 0
        guard d > 1 else { OxAlert.error("Файл не похож на аудио"); return }
        onPick(StoryAudio(url: local, title: title, artist: artist, duration: d))
        dismiss()
    }
}
