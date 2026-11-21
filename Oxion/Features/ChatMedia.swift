import SwiftUI
import AVFoundation
import AVKit

// MARK: - Голосовые и видеокружки в чатах (как в Telegram). Файлы уходят на сервер OXION.

@MainActor
@Observable
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    var recording = false
    var levels: [Float] = []
    var started: Date?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var url: URL?

    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else {
            OxAlert.show(icon: "mic.slash.fill", tint: .orange, title: "Нет доступа к микрофону", message: "Настройки → Oxion → Микрофон")
            return false
        }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? s.setActive(true)
        let u = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
        guard let r = try? AVAudioRecorder(url: u, settings: settings) else { return false }
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        url = u
        levels = []
        started = Date()
        recording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                let p = r.averagePower(forChannel: 0)           // -160…0 дБ
                self.levels.append(max(0, min(1, (p + 50) / 50)))
                if self.duration >= 300 { _ = self.stop() }      // не длиннее 5 минут
            }
        }
        Haptic.tap(.medium)
        return true
    }

    var duration: Double { started.map { Date().timeIntervalSince($0) } ?? 0 }

    /// Закончить запись; nil — если слишком короткая
    func stop() -> (URL, Int, String)? {
        timer?.invalidate(); timer = nil
        let d = duration
        recorder?.stop(); recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url, d >= 0.7 else { return nil }
        return (url, max(1, Int(d.rounded())), Self.wave(levels))
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder?.deleteRecording(); recorder = nil
        recording = false
        Haptic.tap(.soft)
    }

    /// «Волна» для сервера: до 64 цифр 0–9
    static func wave(_ l: [Float]) -> String {
        guard !l.isEmpty else { return "" }
        let n = min(64, l.count)
        return (0..<n).map { i -> String in
            let a = i * l.count / n, b = max(a + 1, (i + 1) * l.count / n)
            let m = l[a..<b].max() ?? 0
            return String(Int((m * 9).rounded()))
        }.joined()
    }
}

/// Запись видеокружка: фронтальная камера + микрофон, до 60 секунд
@MainActor
@Observable
final class VideoNoteRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    var recording = false
    var started: Date?
    var ready = false
    private let output = AVCaptureMovieFileOutput()
    private var finish: ((URL?) -> Void)?

    func prepare() async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video), await AVAudioApplication.requestRecordPermission() else {
            OxAlert.show(icon: "video.slash.fill", tint: .orange, title: "Нет доступа к камере или микрофону", message: "Настройки → Oxion")
            return false
        }
        if !ready {
            session.beginConfiguration()
            session.sessionPreset = .high
            if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
               let i = try? AVCaptureDeviceInput(device: cam), session.canAddInput(i) { session.addInput(i) }
            if let mic = AVCaptureDevice.default(for: .audio), let i = try? AVCaptureDeviceInput(device: mic), session.canAddInput(i) { session.addInput(i) }
            if session.canAddOutput(output) { session.addOutput(output) }
            output.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
            if let c = output.connection(with: .video) {
                if c.isVideoMirroringSupported { c.isVideoMirrored = true }
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            }
            session.commitConfiguration()
            ready = true
        }
        let s = session
        await Task.detached { if !s.isRunning { s.startRunning() } }.value
        return true
    }

    func start() {
        guard ready, !output.isRecording else { return }
        let u = FileManager.default.temporaryDirectory.appending(path: "note-\(UUID().uuidString).mov")
        output.startRecording(to: u, recordingDelegate: self)
        started = Date()
        recording = true
        Haptic.tap(.medium)
    }

    var duration: Double { started.map { Date().timeIntervalSince($0) } ?? 0 }

    func stop(_ done: @escaping (URL?) -> Void) {
        finish = done
        if output.isRecording { output.stopRecording() } else { done(nil) }
    }

    func shutdown() {
        let s = session
        Task.detached { if s.isRunning { s.stopRunning() } }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        MainActor.assumeIsolated {
            recording = false
            let ok = (error == nil) || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
            finish?(ok ? url : nil)
            finish = nil
        }
    }
}

private struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    final class V: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var pl: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> V {
        let v = V(); v.pl.session = session; v.pl.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ v: V, context: Context) {}
}

// MARK: - Кнопка записи (вместо «Отправить», когда поле пустое)

enum RecMode: String { case voice, video }

struct RecordButton: View {
    @AppStorage("chat_rec_mode") private var modeRaw = RecMode.voice.rawValue
    var onVoice: (URL, Int, String) -> Void
    var onVideo: (URL, Int) -> Void

    @State private var voice = VoiceRecorder()
    @State private var video = VideoNoteRecorder()
    @State private var pressStart: Date?
    @State private var drag: CGSize = .zero
    @State private var locked = false
    @State private var active = false

    private var mode: RecMode { RecMode(rawValue: modeRaw) ?? .voice }
    private var cancelling: Bool { drag.width < -110 }

    var body: some View {
        Image(systemName: mode == .voice ? "mic.fill" : "video.circle.fill")
            .font(.title3)
            .foregroundStyle(active ? Color.onLime : .primary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 44, height: 44)
            .background(active ? Color.lime : .clear, in: Circle())
            .scaleEffect(active ? 1.6 : 1)
            .offset(x: active && !locked ? min(0, drag.width) : 0, y: active && !locked ? min(0, drag.height) : 0)
            .glassEffect(active ? .identity : .regular.interactive(), in: .circle)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: active)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if pressStart == nil {
                            pressStart = Date()
                            Task {
                                try? await Task.sleep(for: .milliseconds(220))
                                if pressStart != nil && !active { await begin() }
                            }
                        }
                        drag = v.translation
                        if active && !locked && v.translation.height < -90 {
                            locked = true
                            Haptic.tap(.rigid)
                        }
                    }
                    .onEnded { _ in
                        let short = (pressStart.map { Date().timeIntervalSince($0) } ?? 1) < 0.22
                        pressStart = nil
                        if short && !active {
                            // короткое нажатие — переключить голос ↔ кружок
                            Haptic.tap()
                            modeRaw = mode == .voice ? RecMode.video.rawValue : RecMode.voice.rawValue
                        } else if active && !locked {
                            if cancelling { cancel() } else { finish() }
                        }
                        drag = .zero
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                if active { overlay }
            }
    }

    // оверлей записи: таймер, подсказки, кружок камеры
    @ViewBuilder
    private var overlay: some View {
        RecordingOverlay(mode: mode, voice: voice, video: video, locked: locked, cancelling: cancelling,
                         onSend: { finish() }, onCancel: { cancel() })
    }

    private func begin() async {
        if mode == .voice {
            guard await voice.start() else { return }
        } else {
            guard await video.prepare() else { return }
            video.start()
        }
        withAnimation { active = true }
    }

    private func finish() {
        let m = mode
        withAnimation { active = false; locked = false }
        if m == .voice {
            if let r = voice.stop() { onVoice(r.0, r.1, r.2) }
            else { OxAlert.show(icon: "mic.fill", title: "Удерживайте, чтобы записать") }
        } else {
            let d = Int(video.duration.rounded())
            video.stop { url in
                video.shutdown()
                if let url, d >= 1 { onVideo(url, d) }
            }
        }
    }

    private func cancel() {
        withAnimation { active = false; locked = false }
        if mode == .voice { voice.cancel() } else { video.stop { _ in video.shutdown() } }
    }
}

/// Плашка записи поверх чата: красная точка, время, «‹ отмена», для кружка — круглая камера
private struct RecordingOverlay: View {
    let mode: RecMode
    let voice: VoiceRecorder
    let video: VideoNoteRecorder
    let locked: Bool
    let cancelling: Bool
    var onSend: () -> Void
    var onCancel: () -> Void
    @State private var blink = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let d = mode == .voice ? voice.duration : video.duration
            ZStack(alignment: .bottomTrailing) {
                if mode == .video {
                    ZStack {
                        CameraPreviewLayer(session: video.session)
                            .frame(width: 280, height: 280)
                            .clipShape(Circle())
                        Circle()
                            .trim(from: 0, to: min(1, d / 60))
                            .stroke(Color.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 292, height: 292)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 30)
                    .offset(x: -40, y: -260)
                    .transition(.scale.combined(with: .opacity))
                }
                HStack(spacing: 12) {
                    Circle().fill(Color.red).frame(width: 10, height: 10).opacity(blink ? 0.2 : 1)
                    Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)).font(.body.monospacedDigit().bold())
                    if mode == .voice {
                        HStack(spacing: 2) {
                            ForEach(Array(voice.levels.suffix(22).enumerated()), id: \.offset) { _, l in
                                Capsule().fill(Color.lime).frame(width: 3, height: CGFloat(4 + l * 22))
                            }
                        }
                        .frame(height: 26)
                    }
                    Spacer(minLength: 0)
                    if locked {
                        Button("Отмена", role: .destructive, action: onCancel).font(.subheadline.bold())
                        Button(action: onSend) {
                            Image(systemName: "arrow.up").font(.headline).foregroundStyle(Color.onLime)
                                .frame(width: 40, height: 40).background(Color.lime, in: Circle())
                        }
                    } else {
                        Text(cancelling ? "Отпустите — отмена" : "‹ влево — отмена · ↑ закрепить")
                            .font(.caption)
                            .foregroundStyle(cancelling ? Color.red : .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(width: UIScreen.main.bounds.width - 24)
                .glassEffect(.regular, in: .capsule)
                .offset(x: 6, y: -2)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { blink = true } }
        .allowsHitTesting(locked)
    }
}

// MARK: - Воспроизведение

/// Голосовое: волна, прогресс, скорость, расшифровка через сервер
struct VoiceMessageView: View {
    let url: URL?
    let seconds: Int
    var wave: String = ""
    var tint: Color = .primary
    var messageId: Int?
    var transcript: String?

    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var rate: Float = 1
    @State private var text: String?
    @State private var transcribing = false
    @State private var observer: Any?

    private var bars: [CGFloat] {
        let digits = wave.compactMap { $0.wholeNumberValue }
        let src = digits.isEmpty ? (0..<32).map { ($0 * 7 + 3) % 10 } : digits
        let n = 32
        return (0..<n).map { i in CGFloat(src[i * src.count / n]) / 9 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(bars.enumerated()), id: \.offset) { i, h in
                            Capsule()
                                .fill(Double(i) / Double(bars.count) <= progress ? tint : tint.opacity(0.3))
                                .frame(width: 3, height: 4 + h * 20)
                        }
                    }
                    .frame(height: 24)
                    HStack(spacing: 8) {
                        let shown = playing ? Int(Double(seconds) * (1 - progress)) : seconds
                        Text(String(format: "%d:%02d", shown / 60, shown % 60)).font(.caption.monospacedDigit())
                        if playing {
                            Button(rate == 1 ? "1×" : rate == 1.5 ? "1,5×" : "2×") {
                                rate = rate == 1 ? 1.5 : rate == 1.5 ? 2 : 1
                                player?.rate = rate
                            }
                            .font(.caption2.bold())
                        }
                        if messageId != nil && text == nil {
                            Button { Task { await transcribe() } } label: {
                                if transcribing { ProgressView().controlSize(.mini) } else { Image(systemName: "text.quote") }
                            }
                            .font(.caption)
                        }
                    }
                    .opacity(0.75)
                }
            }
            if let text {
                Text(text).font(.footnote).italic().transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(tint)
        .onAppear { text = transcript }
        .onDisappear { player?.pause(); playing = false }
    }

    private func toggle() {
        guard let url else { return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let p = AVPlayer(url: url)
            player = p
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { t in
                MainActor.assumeIsolated {
                    let total = max(1, Double(seconds))
                    progress = min(1, t.seconds / total)
                    if t.seconds >= total - 0.05 { playing = false; progress = 0; player?.seek(to: .zero) }
                }
            }
        }
        if playing { player?.pause() } else { player?.play(); player?.rate = rate }
        playing.toggle()
        Haptic.tap()
    }

    private struct TR: Decodable { let text: String? }
    private func transcribe() async {
        guard let id = messageId else { return }
        transcribing = true
        defer { transcribing = false }
        do {
            let r: TR = try await API.call("/messages/\(id)/transcribe", method: "POST")
            withAnimation { text = (r.text?.isEmpty == false) ? r.text : "Не удалось разобрать речь" }
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

/// Видеокружок: без звука крутится по кругу, нажатие — со звуком сначала
struct VideoNoteView: View {
    let url: URL?
    let seconds: Int
    @State private var player: AVPlayer?
    @State private var loud = false
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            if let player {
                VideoLayer(player: player)
            } else {
                Color.black.opacity(0.3)
                ProgressView()
            }
            if loud {
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
            } else {
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.slash.fill")
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture { toggleSound() }
        .onAppear { setup() }
        .onDisappear { player?.pause() }
    }

    private func setup() {
        guard player == nil, let url else { return }
        let p = AVPlayer(url: url)
        p.isMuted = true
        p.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            MainActor.assumeIsolated {
                p.seek(to: .zero)
                if loud { loud = false; p.isMuted = true }
                p.play()
            }
        }
        p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { t in
            MainActor.assumeIsolated { progress = min(1, t.seconds / max(1, Double(seconds))) }
        }
        player = p
        p.play()
    }

    private func toggleSound() {
        guard let p = player else { return }
        Haptic.tap()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        loud.toggle()
        p.isMuted = !loud
        if loud { p.seek(to: .zero) }
        p.play()
    }
}

private struct VideoLayer: UIViewRepresentable {
    let player: AVPlayer
    final class V: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var pl: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> V { let v = V(); v.pl.player = player; v.pl.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ v: V, context: Context) { v.pl.player = player }
}

/// Обычное видео в чате
struct ChatVideoView: View {
    let url: URL?
    let seconds: Int
    @State private var full = false
    var body: some View {
        ZStack {
            Color.black
            Image(systemName: "play.circle.fill").font(.system(size: 48)).foregroundStyle(.white.opacity(0.9))
            VStack { Spacer(); HStack { Spacer()
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).font(.caption2.bold()).foregroundStyle(.white)
                    .padding(6).background(.black.opacity(0.4), in: Capsule()).padding(8) } }
        }
        .frame(width: 240, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { full = true }
        .fullScreenCover(isPresented: $full) {
            if let url { VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea().overlay(alignment: .topTrailing) {
                Button { full = false } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44) }
                    .glassEffect(.regular.interactive(), in: .circle).padding()
            } }
        }
    }
}
