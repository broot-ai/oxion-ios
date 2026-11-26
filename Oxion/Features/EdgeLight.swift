import SwiftUI
import UIKit
import AVFoundation
import Photos

// MARK: - Кольцевая подсветка экрана (как Edge Light на Mac)
// Экран iPhone светится мягкой рамкой по краям и работает как кольцевая лампа для фронтальной камеры.
// Работает только внутри Oxion (камера историй, кружки, экран «Кольцевая лампа»): iOS не даёт приложениям
// рисовать поверх других приложений и вмешиваться в чужую камеру — это честное ограничение системы.

@MainActor @Observable
final class EdgeLight {
    static let shared = EdgeLight()

    enum Preset: String, CaseIterable, Identifiable {
        case cold, neutral, warm, auto
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cold: "Холодный"
            case .neutral: "Нейтральный"
            case .warm: "Тёплый"
            case .auto: "Авто"
            }
        }
        var kelvin: Double {
            switch self {
            case .cold: 6500
            case .neutral: 5000
            case .warm: 3200
            case .auto: 5200
            }
        }
    }

    // настройки (сохраняются)
    var brightness: Double { didSet { save() } }      // 0…1
    var width: Double { didSet { save() } }           // 0.05…0.40 от короткой стороны экрана
    var kelvin: Double { didSet { save() } }          // 2700…6500
    var preset: Preset { didSet { save() } }
    var auto: Bool { didSet { save() } }              // авто-яркость по освещению
    var followFace: Bool { didSet { save() } }        // ярче со стороны лица
    var autoFront: Bool { didSet { save() } }         // сама включается на фронтальной камере
    var forNotes: Bool { didSet { save() } }          // в кружках

    // состояние
    var on = false
    var face: CGRect?          // лицо в долях экрана (0…1), если видно
    var ambient: Double = 0.4  // 0 — светло, 1 — темно (по ISO камеры)
    private var savedBrightness: CGFloat?
    private var users = 0

    private init() {
        let d = UserDefaults.standard
        brightness = d.object(forKey: "el.b") as? Double ?? 0.9
        width = d.object(forKey: "el.w") as? Double ?? 0.16
        kelvin = d.object(forKey: "el.k") as? Double ?? 5000
        preset = Preset(rawValue: d.string(forKey: "el.p") ?? "") ?? .neutral
        auto = d.object(forKey: "el.a") as? Bool ?? true
        followFace = d.object(forKey: "el.f") as? Bool ?? true
        autoFront = d.object(forKey: "el.af") as? Bool ?? false
        forNotes = d.object(forKey: "el.n") as? Bool ?? false
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(brightness, forKey: "el.b"); d.set(width, forKey: "el.w"); d.set(kelvin, forKey: "el.k")
        d.set(preset.rawValue, forKey: "el.p"); d.set(auto, forKey: "el.a"); d.set(followFace, forKey: "el.f")
        d.set(autoFront, forKey: "el.af"); d.set(forNotes, forKey: "el.n")
    }

    /// фактическая сила света: в авто — чем темнее вокруг, тем ярче и шире
    var intensity: Double { auto ? min(1, max(0.35, brightness * (0.7 + 0.45 * ambient))) : brightness }
    var band: Double { auto ? min(0.40, max(0.05, width * (0.8 + 0.7 * ambient))) : width }
    var effectiveKelvin: Double {
        guard preset == .auto else { return kelvin }
        // авто: в темноте — теплее (мягче для глаз), при свете — нейтрально
        return 5600 - 1600 * ambient
    }
    var color: Color { Self.color(kelvin: effectiveKelvin) }

    /// Включение: экран на максимум яркости (iOS вернёт прежнюю, когда выключим)
    func acquire() {
        users += 1
        guard !on else { return }
        on = true
        if let s = Self.screen {
            if savedBrightness == nil { savedBrightness = s.brightness }
            s.brightness = 1
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0, on else { return }
        on = false
        face = nil
        if let s = Self.screen, let b = savedBrightness { s.brightness = b }
        savedBrightness = nil
    }

    func toggle() { on ? forceOff() : acquire() }
    func forceOff() { users = 1; release() }

    private static var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }

    /// Освещённость по камере: высокий ISO / длинная выдержка = темно
    func updateAmbient(from device: AVCaptureDevice?) {
        guard let d = device else { return }
        let lo = Double(d.activeFormat.minISO), hi = min(Double(d.activeFormat.maxISO), 1600)
        let iso = Double(d.iso)
        let exp = d.exposureDuration.seconds
        var a = hi > lo ? (iso - lo) / (hi - lo) : 0.4
        if exp > 1.0 / 30 { a = max(a, 0.85) }
        let v = min(1, max(0, a))
        // сглаживание — без мерцания
        ambient = ambient * 0.8 + v * 0.2
    }

    /// Цвет по цветовой температуре (приближение Таннера Хелланда)
    static func color(kelvin: Double) -> Color {
        let t = kelvin / 100
        var r: Double, g: Double, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
            b = t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
            b = 255
        }
        func c(_ x: Double) -> Double { min(255, max(0, x)) / 255 }
        return Color(red: c(r), green: c(g), blue: c(b))
    }
}

// MARK: - Сама рамка света

struct EdgeLightOverlay: View {
    @State private var light = EdgeLight.shared
    var corner: CGFloat = 56

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let w = min(W, H) * light.band
            let col = light.color
            ZStack {
                // мягкая рамка: заливка минус размытая «дыра» в центре → плавный переход к центру
                col
                // ярче со стороны лица: свет «тянется» к лицу
                if light.followFace, let f = light.face {
                    RadialGradient(colors: [.white.opacity(0.9), .clear], center: UnitPoint(x: 0, y: f.midY), startRadius: 0, endRadius: w * 3)
                    RadialGradient(colors: [.white.opacity(0.9), .clear], center: UnitPoint(x: 1, y: f.midY), startRadius: 0, endRadius: w * 3)
                    RadialGradient(colors: [.white.opacity(0.6), .clear], center: UnitPoint(x: f.midX, y: 0), startRadius: 0, endRadius: w * 2.5)
                }
            }
            .mask {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.white)
                    RoundedRectangle(cornerRadius: max(8, corner - w * 0.5), style: .continuous)
                        .padding(w)
                        .blur(radius: w * 0.55)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .opacity(light.intensity)
            .animation(.smooth(duration: 0.45), value: light.face)
            .animation(.smooth(duration: 0.6), value: light.band)
            .animation(.smooth(duration: 0.6), value: light.intensity)
            .drawingGroup()
            .frame(width: W, height: H)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}

// MARK: - Настройки света (панель из стекла)

struct EdgeLightControls: View {
    @Bindable var light = EdgeLight.shared
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(EdgeLight.Preset.allCases) { p in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) {
                            light.preset = p
                            if p != .auto { light.kelvin = p.kelvin }
                        }
                        Haptic.tap(.soft)
                    } label: {
                        Text(p.title).font(.subheadline.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .foregroundStyle(light.preset == p ? Color.black : .white)
                            .background(light.preset == p ? AnyShapeStyle(EdgeLight.color(kelvin: p.kelvin)) : AnyShapeStyle(Color.white.opacity(0.1)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            row("sun.max.fill", "Яркость", "\(Int(light.brightness * 100))%") {
                Slider(value: $light.brightness, in: 0...1)
            }
            row("square.dashed", "Ширина рамки", "\(Int(light.width * 100))%") {
                Slider(value: $light.width, in: 0.05...0.40)
            }
            if light.preset != .auto {
                row("thermometer.medium", "Температура", "\(Int(light.kelvin)) K") {
                    Slider(value: $light.kelvin, in: 2700...6500)
                        .tint(EdgeLight.color(kelvin: light.kelvin))
                }
            }
            if !compact {
                Toggle(isOn: $light.auto) { Label("Авто-яркость по освещению", systemImage: "wand.and.stars") }
                Toggle(isOn: $light.followFace) { Label("Ярче со стороны лица", systemImage: "face.smiling") }
                Toggle(isOn: $light.autoFront) { Label("Включать на фронтальной камере", systemImage: "camera.rotate") }
                Toggle(isOn: $light.forNotes) { Label("Подсветка в кружках", systemImage: "video.circle") }
            }
        }
        .tint(Color.lime)
        .foregroundStyle(.white)
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func row<C: View>(_ icon: String, _ t: String, _ v: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(t, systemImage: icon).font(.subheadline.weight(.semibold))
                Spacer()
                Text(v).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            c()
        }
    }
}

// MARK: - Экран «Кольцевая лампа»: селфи, Stories 9:16, видео и лампа для звонка

struct RingLightScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cam = StoryCameraModel()
    @State private var light = EdgeLight.shared
    @State private var mode: Mode = .selfie
    @State private var showPanel = false
    @State private var toast: String?
    @State private var lastShot: UIImage?

    enum Mode: String, CaseIterable, Identifiable {
        case selfie, stories, video, lamp
        var id: String { rawValue }
        var title: String {
            switch self {
            case .selfie: "Селфи"
            case .stories: "Stories"
            case .video: "Видео"
            case .lamp: "Лампа"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if mode == .lamp {
                // лампа для звонка на другом устройстве: весь экран — мягкий свет нужной температуры
                light.color.opacity(light.intensity).ignoresSafeArea()
                    .onTapGesture { withAnimation { showPanel.toggle() } }
            } else if cam.ready {
                LitCameraPreview(cam: cam)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .padding(.horizontal, mode == .stories ? 0 : 0)
                    .aspectRatio(mode == .stories ? 9.0 / 16.0 : nil, contentMode: .fit)
                    .padding(light.band * 0.6 * UIScreen.main.bounds.width)
            } else if cam.denied {
                ContentUnavailableView("Нет доступа к камере", systemImage: "camera.fill",
                                       description: Text("Разрешите камеру в Настройках, чтобы подсветка работала вместе с камерой"))
            }
            if mode != .lamp { EdgeLightOverlay() }
            controls
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            light.acquire()
            await cam.prepare(front: true)
            // освещённость — по ISO камеры, раз в полсекунды
            while !Task.isCancelled {
                light.updateAmbient(from: cam.device)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .onDisappear {
            cam.shutdown()
            light.release()
        }
        .onChange(of: mode) { _, m in
            if m == .lamp { cam.shutdown() } else { Task { await cam.prepare(front: true) } }
        }
        .overlay(alignment: .top) {
            if let t = toast {
                Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // управление одной рукой: всё внизу
    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 46, height: 46)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                Spacer()
                Button { withAnimation(.smooth) { showPanel.toggle() } } label: {
                    Image(systemName: "slider.horizontal.3").font(.headline).frame(width: 46, height: 46)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            Spacer()
            if showPanel {
                EdgeLightControls(compact: false)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if mode != .lamp { shutter }
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 30)
            .padding(.bottom, 10)
        }
    }

    private var shutter: some View {
        let rec = cam.recording
        let isVideo = mode == .video || mode == .stories
        return Button {
            if isVideo {
                if rec {
                    cam.stopVideo { url in handleVideo(url) }
                } else { cam.startVideo() }
            } else {
                cam.shoot { img in
                    guard let img else { return }
                    lastShot = img
                    save(image: img)
                }
            }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 5).frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: rec ? 8 : 32, style: .continuous)
                    .fill(isVideo ? Color.red : .white)
                    .frame(width: rec ? 30 : 64, height: rec ? 30 : 64)
                    .animation(.spring(duration: 0.3), value: rec)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if rec {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let s = Int(cam.elapsed)
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.red, in: Capsule())
                }
                .offset(y: -36)
            }
        }
    }

    private func handleVideo(_ url: URL?) {
        guard let url else { return }
        if mode == .stories {
            // готовое вертикальное видео — сразу в редактор истории
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                StoriesStore.shared.shareDraft = StoryPreset(media: .video(url))
            }
        } else {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, _ in Task { @MainActor in show(ok ? "Видео сохранено в «Фото»" : "Нет доступа к «Фото»") } }
        }
    }

    private func save(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        show("Фото сохранено в «Фото»")
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        Task { try? await Task.sleep(for: .seconds(1.8)); withAnimation { toast = nil } }
    }
}

/// Превью камеры, которое сообщает модели положение лица (через публичный AVCaptureVideoPreviewLayer)
struct LitCameraPreview: UIViewRepresentable {
    let cam: StoryCameraModel
    final class V: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var pl: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> V {
        let v = V()
        v.pl.session = cam.session
        v.pl.videoGravity = .resizeAspectFill
        cam.previewLayer = v.pl
        return v
    }
    func updateUIView(_ v: V, context: Context) { cam.previewLayer = v.pl }
}

// MARK: - Настройки в профиле

struct EdgeLightSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var preview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button { model.ringLight = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.max.fill").font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Открыть «Кольцевую лампу»").font(.headline)
                            Text("Селфи, Stories 9:16, видео и лампа для звонка").font(.caption).opacity(0.7)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(Color.onLime)
                    .padding(16)
                    .background(Color.lime, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
                .buttonStyle(.plain)

                EdgeLightControls()
                    .environment(\.colorScheme, .dark)

                Toggle(isOn: $preview) { Label("Показать подсветку сейчас", systemImage: "eye") }
                    .tint(Color.lime)
                    .padding(16)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 30, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Label("Где работает", systemImage: "info.circle").font(.headline)
                    Text("Подсветка включается в камере историй (значок лампочки сверху; удержание — настройки), в «Кольцевой лампе» и в кружках в чатах. Экран светится мягкой рамкой и подстраивается под освещение и положение лица.")
                    Text("Поверх Instagram, Telegram, FaceTime и других приложений iOS не разрешает рисовать никому — это ограничение системы. Для звонка в другом приложении используйте режим «Лампа» на втором устройстве или снимайте в Oxion.")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(16)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .padding(16)
        }
        .navigationTitle("Кольцевая подсветка")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if preview { EdgeLightOverlay() } }
        .onChange(of: preview) { _, on in on ? EdgeLight.shared.acquire() : EdgeLight.shared.release() }
        .onDisappear { if preview { preview = false; EdgeLight.shared.release() } }
    }
}
