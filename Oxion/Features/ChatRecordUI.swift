import SwiftUI
import AVFoundation

// MARK: - Запись голосовых и кружков — как в Telegram iOS
// Удержание микрофона → большой круг с «дыханием» от громкости, слева красная точка и таймер 0:00,00,
// по центру «‹ Влево — отмена», сверху замок. Вверх — закрепить (круг → «↑», сверху пауза, по центру «Отмена»).
// Пауза → предпросмотр: корзина, волна с ▶ и длительностью, кнопка «Отправить», сверху микрофон — дописать.
// Влево — отмена: точка падает в корзину. Короткое нажатие — переключить звук ↔ видео с подсказкой.

enum RecPhase: Equatable { case idle, holding, locked, preview, cancelling }

/// Голос по кускам: пауза закрывает кусок, «дописать» начинает новый; при отправке куски склеиваются.
@MainActor @Observable
final class SegmentVoiceRecorder: NSObject {
    var recording = false
    var levels: [Float] = []
    var level: Float = 0
    private(set) var segments: [URL] = []
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var segStart: Date?
    private var done: Double = 0

    var duration: Double { done + (segStart.map { Date().timeIntervalSince($0) } ?? 0) }

    private var prepared: (AVAudioRecorder, URL)?
    private var warming: Task<Void, Never>?

    /// Заготовка в момент касания: сессия звука и файл готовы заранее, запись стартует мгновенно
    func warmUp() {
        guard prepared == nil, warming == nil, AVAudioApplication.shared.recordPermission == .granted else { return }
        warming = Task { @MainActor in
            defer { warming = nil }
            _ = makeRecorder()
        }
    }
    /// Короткое нажатие — заготовка не понадобилась
    func coolDown() {
        guard !recording else { return }
        if let p = prepared { p.0.deleteRecording(); prepared = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    @discardableResult
    private func makeRecorder() -> Bool {
        if prepared != nil { return true }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? s.setActive(true)
        let u = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
        guard let r = try? AVAudioRecorder(url: u, settings: settings) else { return false }
        r.isMeteringEnabled = true
        r.prepareToRecord()
        prepared = (r, u)
        return true
    }

    func begin(fresh: Bool) async -> Bool {
        if fresh {
            if AVAudioApplication.shared.recordPermission != .granted {
                // первый раз iOS спросит доступ — после ответа нужно нажать ещё раз
                guard await AVAudioApplication.requestRecordPermission() else {
                    OxAlert.show(icon: "mic.slash.fill", tint: .orange, title: "Нет доступа к микрофону", message: "Настройки → Oxion → Микрофон")
                    return false
                }
            }
            segments = []; levels = []; done = 0
        }
        if let w = warming { await w.value }
        guard makeRecorder(), let p = prepared else { return false }
        let r = p.0, u = p.1
        prepared = nil
        r.record()
        recorder = r
        segments.append(u)
        segStart = Date()
        recording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                let v = max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50))
                self.level = v
                self.levels.append(v)
                if self.duration >= 300 { self.pause() }
            }
        }
        return true
    }

    /// закрыть текущий кусок (для паузы и перед отправкой)
    func pause() {
        timer?.invalidate(); timer = nil
        if let st = segStart { done += Date().timeIntervalSince(st) }
        segStart = nil
        recorder?.stop(); recorder = nil
        recording = false
        level = 0
    }

    func cancel() {
        pause()
        for u in segments { try? FileManager.default.removeItem(at: u) }
        segments = []; levels = []; done = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Итоговый файл: один кусок — как есть, несколько — склеиваем
    func finish() async -> (URL, Int, String)? {
        pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let d = done
        guard d >= 0.7, !segments.isEmpty else { return nil }
        var url = segments[0]
        if segments.count > 1 {
            let comp = AVMutableComposition()
            guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            var at = CMTime.zero
            for u in segments {
                let a = AVURLAsset(url: u)
                guard let t = try? await a.loadTracks(withMediaType: .audio).first, let dur = try? await a.load(.duration) else { continue }
                try? track.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: t, at: at)
                at = at + dur
            }
            let out = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
            guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else { return nil }
            do { try await ex.export(to: out, as: .m4a); url = out } catch { return nil }
        }
        return (url, max(1, Int(d.rounded())), VoiceRecorder.wave(levels))
    }
}

@MainActor @Observable
final class ChatRecorder {
    var phase: RecPhase = .idle
    var drag: CGSize = .zero
    var tip: String?
    let voice = SegmentVoiceRecorder()
    let video = VideoNoteRecorder()
    var modeRaw: String = UserDefaults.standard.string(forKey: "chat_rec_mode") ?? RecMode.voice.rawValue {
        didSet { UserDefaults.standard.set(modeRaw, forKey: "chat_rec_mode") }
    }
    var mode: RecMode { RecMode(rawValue: modeRaw) ?? .voice }

    // предпросмотр
    var playing = false
    var playProgress: Double = 0
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var playTimer: Timer?
    @ObservationIgnored private var playBefore: Double = 0
    @ObservationIgnored private var playItem: AVPlayerItem?

    @ObservationIgnored var onVoice: ((URL, Int, String) -> Void)?
    @ObservationIgnored var onVideo: ((URL, Int) -> Void)?

    var active: Bool { phase != .idle }
    var duration: Double { mode == .voice ? voice.duration : video.duration }
    var level: Float { mode == .voice ? voice.level : 0.35 }
    var lockProgress: CGFloat { min(1, max(0, -drag.height / 70)) }
    var cancelProgress: CGFloat { min(1, max(0, -drag.width / 130)) }

    func toggleMode() {
        modeRaw = mode == .voice ? RecMode.video.rawValue : RecMode.voice.rawValue
        tip = mode == .voice ? String(localized: "Звук — удерживайте. Видео — нажмите.") : String(localized: "Видео — удерживайте. Звук — нажмите.")
        Haptic.tap()
        let t = tip
        Task { try? await Task.sleep(for: .seconds(2.4)); if tip == t { withAnimation(.easeOut(duration: 0.25)) { tip = nil } } }
    }

    /// касание: заранее готовим микрофон, пока палец ещё не «удержал»
    @ObservationIgnored var pressing = false
    func touchDown() { pressing = true; if mode == .voice { voice.warmUp() } }
    func touchUp() { pressing = false }
    func touchCancelled() { if mode == .voice && phase == .idle { voice.coolDown() } }

    func begin() async {
        tip = nil
        if mode == .voice {
            guard await voice.begin(fresh: true) else { return }
        } else {
            guard await video.prepare() else { return }
            video.start()
        }
        // палец отпустили, пока микрофон включался, — тихо отменяем
        guard pressing else {
            if mode == .voice { voice.cancel() } else { video.stop { [weak self] _ in self?.video.shutdown() } }
            return
        }
        withAnimation(.spring(duration: 0.3, bounce: 0.35)) { phase = .holding }
    }

    func lock() {
        guard phase == .holding else { return }
        Haptic.tap(.rigid)
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { phase = .locked; drag = .zero }
    }

    func pauseToPreview() {
        guard phase == .locked, mode == .voice else { return }
        voice.pause()
        Haptic.tap(.light)
        withAnimation(.spring(duration: 0.35)) { phase = .preview }
    }

    func resume() async {
        stopPlayback()
        guard await voice.begin(fresh: false) else { return }
        Haptic.tap(.medium)
        withAnimation(.spring(duration: 0.35)) { phase = .locked }
    }

    func send() {
        stopPlayback()
        let m = mode
        withAnimation(.spring(duration: 0.3)) { phase = .idle; drag = .zero }
        if m == .voice {
            Task {
                if let r = await voice.finish() { onVoice?(r.0, r.1, r.2) }
                else { OxAlert.show(icon: "mic.fill", title: String(localized: "Удерживайте, чтобы записать")) }
            }
        } else {
            let d = Int(video.duration.rounded())
            video.stop { [weak self] url in
                self?.video.shutdown()
                if let url, d >= 1 { self?.onVideo?(url, d) }
            }
        }
    }

    func cancel() {
        guard phase != .idle && phase != .cancelling else { return }
        stopPlayback()
        if mode == .voice { voice.cancel() } else { video.stop { [weak self] _ in self?.video.shutdown() } }
        Haptic.tap(.soft)
        withAnimation(.spring(duration: 0.3)) { phase = .cancelling; drag = .zero }
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.spring(duration: 0.35)) { if phase == .cancelling { phase = .idle } }
        }
    }

    // MARK: прослушивание до отправки
    func togglePlay() {
        if playing { player?.pause(); playing = false; return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            let items = voice.segments.map { AVPlayerItem(url: $0) }
            player = AVQueuePlayer(items: items)
            playProgress = 0
        }
        player?.play()
        playing = true
        let total = max(0.1, voice.duration)
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.player else { return }
                if let it = p.currentItem {
                    if let last = self.playItem, last !== it { self.playBefore += last.duration.seconds.isFinite ? last.duration.seconds : 0 }
                    self.playItem = it
                    self.playProgress = min(1, (self.playBefore + p.currentTime().seconds) / total)
                } else {
                    self.stopPlayback()
                }
            }
        }
    }

    func stopPlayback() {
        playTimer?.invalidate(); playTimer = nil
        player?.pause(); player = nil
        playing = false
        playProgress = 0
        playBefore = 0
        playItem = nil
    }
}

// MARK: - Кнопка микрофона (держит жест, рисует большой круг и замок)

struct ChatMicButton: View {
    @Bindable var rec: ChatRecorder
    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?

    private let big: CGFloat = 78

    var body: some View {
        ZStack {
            if rec.phase == .preview {
                Button { rec.send() } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.onLime)
                        .frame(width: 44, height: 44)
                        .background(Color.lime, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: rec.mode == .voice ? "mic" : "camera")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .opacity(rec.active ? 0.011 : 1)
                    .contentShape(Circle())
                    .gesture(press)
            }
        }
        .frame(width: 44, height: 44)
        // большой круг и замок — поверх, за пределами кнопки
        .overlay {
            if rec.phase == .holding || rec.phase == .locked {
                bigCircle
                    .offset(x: rec.phase == .holding ? min(0, rec.drag.width) * 0.9 : 0,
                            y: rec.phase == .holding ? max(-50, min(0, rec.drag.height)) * 0.6 : 0)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            topPill
        }
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if pressStart == nil {
                    pressStart = Date()
                    rec.touchDown()
                    holdTask = Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled, pressStart != nil, rec.phase == .idle else { return }
                        Haptic.tap(.medium)
                        await rec.begin()
                    }
                }
                guard rec.phase == .holding else { return }
                rec.drag = v.translation
                if v.translation.height < -70 { rec.lock() }
                else if v.translation.width < -130 { rec.cancel() }
            }
            .onEnded { _ in
                let short = (pressStart.map { Date().timeIntervalSince($0) } ?? 1) < 0.12
                pressStart = nil
                holdTask?.cancel()
                rec.touchUp()
                if rec.phase == .holding { rec.send() }
                else if short && rec.phase == .idle { rec.touchCancelled(); rec.toggleMode() }
                else if rec.phase == .idle { rec.touchCancelled() }
                if rec.phase != .locked { rec.drag = .zero }
            }
    }

    private var bigCircle: some View {
        let lvl = CGFloat(rec.level)
        return ZStack {
            // «дыхание» от громкости, как у Telegram
            Circle().fill(Color.lime.opacity(0.22))
                .frame(width: big, height: big)
                .scaleEffect(1.08 + lvl * 0.55)
                .animation(.spring(response: 0.18, dampingFraction: 0.6), value: lvl)
            Circle().fill(Color.lime.opacity(0.35))
                .frame(width: big, height: big)
                .scaleEffect(1.02 + lvl * 0.28)
                .animation(.spring(response: 0.14, dampingFraction: 0.7), value: lvl)
            Circle().fill(Color.lime).frame(width: big, height: big)
                .shadow(color: Color.lime.opacity(0.35), radius: 12)
            if rec.phase == .locked {
                Button { rec.send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.onLime)
                        .frame(width: big, height: big)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: rec.mode == .voice ? "mic.fill" : "video.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.onLime)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: big, height: big)
    }

    @ViewBuilder private var topPill: some View {
        Group {
            if rec.phase == .holding {
                // замок: поднимается и «защёлкивается», пока тянете вверх
                VStack(spacing: 4) {
                    Image(systemName: rec.lockProgress > 0.85 ? "lock.fill" : "lock")
                        .font(.system(size: 17, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(1 - rec.lockProgress)
                }
                .foregroundStyle(.primary)
                .frame(width: 40, height: 66 - rec.lockProgress * 22)
                .glassEffect(.regular, in: .capsule)
                .offset(y: -(big / 2 + 34) - rec.lockProgress * 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            } else if rec.phase == .locked && rec.mode == .voice {
                Button { rec.pauseToPreview() } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .offset(y: -(big / 2 + 30))
                .transition(.scale.combined(with: .opacity))
            } else if rec.phase == .preview {
                Button { Task { await rec.resume() } } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .offset(y: -54)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: rec.phase)
    }
}

// MARK: - Плашка записи на месте поля ввода

struct ChatRecordPanel: View {
    @Bindable var rec: ChatRecorder
    @State private var blink = false

    var body: some View {
        Group {
            switch rec.phase {
            case .holding, .locked: recordingRow
            case .preview: previewRow
            case .cancelling: cancellingRow
            case .idle: EmptyView()
            }
        }
        .transition(.opacity)
    }

    private func timeText(_ d: Double) -> String {
        let cs = Int((d * 100).rounded(.down))
        return String(format: "%d:%02d,%02d", cs / 6000, (cs / 100) % 60, cs % 100)
    }

    private var panelBG: some View {
        Capsule().fill(Color(.secondarySystemBackground))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var recordingRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: 0xFF3B30)).frame(width: 9, height: 9)
                .opacity(blink ? 0.15 : 1)
                .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever()) { blink = true } }
            TimelineView(.periodic(from: .now, by: 0.03)) { _ in
                Text(timeText(rec.duration))
                    .font(.system(size: 16, weight: .regular).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .frame(width: 74, alignment: .leading)
            ZStack {
                if rec.phase == .locked {
                    Button { rec.cancel() } label: {
                        Text("Отмена")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.limeInk)
                            .padding(.horizontal, 10).frame(height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // «‹ Влево — отмена» уезжает за пальцем и тает
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text("Влево — отмена").font(.system(size: 15))
                    }
                    .foregroundStyle(.secondary)
                    .offset(x: rec.drag.width * 0.5)
                    .opacity(1 - Double(rec.cancelProgress) * 0.9)
                    .phaseAnimator([CGFloat(0), -5, 0]) { v, p in v.offset(x: p) } animation: { _ in .easeInOut(duration: 0.8) }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            Color.clear.frame(width: 36)   // место под большой круг
        }
        .padding(.leading, 16)
        .frame(height: 44)
        .background(panelBG)
        .animation(.spring(duration: 0.3), value: rec.phase)
    }

    private var previewRow: some View {
        HStack(spacing: 8) {
            Button { rec.cancel() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 19))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            ZStack {
                // волна записи, прослушанная часть ярче
                GeometryReader { g in
                    let bars = Self.bars(rec.voice.levels, count: max(12, Int(g.size.width / 5)))
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(bars.enumerated()), id: \.offset) { i, l in
                            Capsule()
                                .fill(Double(i) / Double(max(1, bars.count)) <= rec.playProgress && rec.playProgress > 0 ? Color.onLime : Color.onLime.opacity(0.4))
                                .frame(width: 3, height: max(3, CGFloat(l) * 22))
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
                .padding(.horizontal, 14)
                // ручки обрезки, как у Telegram
                HStack {
                    Capsule().fill(Color.onLime).frame(width: 3, height: 18)
                    Spacer()
                    Capsule().fill(Color.onLime).frame(width: 3, height: 18)
                }
                .padding(.horizontal, 7)
                Button { rec.togglePlay() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: rec.playing ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .bold))
                        Text(String(format: "%d:%02d", Int(rec.voice.duration) / 60, Int(rec.voice.duration.rounded()) % 60))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(Color.lime)
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Color.onLime.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 40)
            .background(Color.lime, in: Capsule())
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var cancellingRow: some View {
        HStack(spacing: 10) {
            // точка падает в корзину, крышка захлопывается
            Image(systemName: "trash.fill")
                .font(.system(size: 19))
                .foregroundStyle(Color(hex: 0xFF3B30))
                .symbolEffect(.bounce.down, options: .nonRepeating)
                .transition(.scale.combined(with: .opacity))
            Spacer()
        }
        .padding(.leading, 13)
        .frame(height: 44)
        .background(panelBG.opacity(0.0))
    }

    static func bars(_ l: [Float], count: Int) -> [Float] {
        guard !l.isEmpty else { return Array(repeating: 0.1, count: count) }
        return (0..<count).map { i in
            let a = i * l.count / count, b = max(a + 1, (i + 1) * l.count / count)
            return l[min(a, l.count - 1)..<min(b, l.count)].max() ?? 0.1
        }
    }
}

/// Подсказка над кнопкой после короткого нажатия
struct ChatRecTip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
    }
}

/// Кружок камеры во время записи видео
struct ChatVideoNoteLive: View {
    let rec: ChatRecorder
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            ZStack {
                CameraPreviewLayer(session: rec.video.session)
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())
                Circle()
                    .trim(from: 0, to: min(1, rec.video.duration / 60))
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 292, height: 292)
            }
            .shadow(color: .black.opacity(0.4), radius: 30)
        }
        .transition(.scale.combined(with: .opacity))
        .allowsHitTesting(false)
    }
}
