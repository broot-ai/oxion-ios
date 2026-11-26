import SwiftUI
import AVFoundation
import Photos
import PhotosUI

// MARK: - Камера для историй как в Telegram
// Сразу открывается камера. Снизу: слева кружок с последним фото (галерея), по центру ВИДЕО / ФОТО,
// справа — смена камеры. В режиме ФОТО: нажатие — снимок, удержание — видео. В режиме ВИДЕО: нажатие — старт/стоп.

@MainActor @Observable
final class StoryCameraModel: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var ready = false
    var denied = false
    var recording = false
    var started: Date?
    var front = false
    var flash = false
    private let photo = AVCapturePhotoOutput()
    private let movie = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private let faces = AVCaptureMetadataOutput()
    /// слой превью — чтобы перевести лицо в координаты экрана (для подсветки)
    @ObservationIgnored weak var previewLayer: AVCaptureVideoPreviewLayer?
    var device: AVCaptureDevice? { videoInput?.device }
    private var onPhoto: ((UIImage?) -> Void)?
    private var onMovie: ((URL?) -> Void)?

    func prepare(front startFront: Bool = false) async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        _ = await AVAudioApplication.requestRecordPermission()
        if !ready {
            session.beginConfiguration()
            session.sessionPreset = .high
            setCamera(front: startFront)
            if let mic = AVCaptureDevice.default(for: .audio), let i = try? AVCaptureDeviceInput(device: mic), session.canAddInput(i) { session.addInput(i) }
            if session.canAddOutput(photo) { session.addOutput(photo) }
            if session.canAddOutput(movie) { session.addOutput(movie) }
            movie.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
            // лица — аппаратное распознавание камеры (дёшево по батарее), для «подсветки к лицу»
            if session.canAddOutput(faces) {
                session.addOutput(faces)
                if faces.availableMetadataObjectTypes.contains(.face) {
                    faces.metadataObjectTypes = [.face]
                    faces.setMetadataObjectsDelegate(self, queue: .main)
                }
            }
            session.commitConfiguration()
            orient()
            ready = true
        }
        let s = session
        await Task.detached { if !s.isRunning { s.startRunning() } }.value
    }

    private func setCamera(front f: Bool) {
        if let v = videoInput { session.removeInput(v) }
        let types: [AVCaptureDevice.DeviceType] = f ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
                                                    : [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let dev = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: f ? .front : .back).devices.first
        if let dev, let i = try? AVCaptureDeviceInput(device: dev), session.canAddInput(i) {
            session.addInput(i)
            videoInput = i
            // на мульти-камерах начинаем с обычного 1×, а не с широкоугольной
            if !f, let sw = dev.virtualDeviceSwitchOverVideoZoomFactors.first, (try? dev.lockForConfiguration()) != nil {
                dev.videoZoomFactor = CGFloat(truncating: sw)
                dev.unlockForConfiguration()
            }
        }
        front = f
    }

    private func orient() {
        for out in [photo as AVCaptureOutput, movie] {
            if let c = out.connection(with: .video) {
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = front }
            }
        }
    }

    func flip() {
        guard ready, !recording else { return }
        session.beginConfiguration()
        setCamera(front: !front)
        session.commitConfiguration()
        orient()
        Haptic.tap(.light)
    }

    func zoom(_ factor: CGFloat) {
        guard let d = videoInput?.device, (try? d.lockForConfiguration()) != nil else { return }
        d.videoZoomFactor = max(d.minAvailableVideoZoomFactor, min(min(d.maxAvailableVideoZoomFactor, 15), factor))
        d.unlockForConfiguration()
    }
    var zoomFactor: CGFloat { videoInput?.device.videoZoomFactor ?? 1 }

    func shoot(_ done: @escaping (UIImage?) -> Void) {
        guard ready else { return }
        onPhoto = done
        let st = AVCapturePhotoSettings()
        if photo.supportedFlashModes.contains(.on) { st.flashMode = flash ? .on : .off }
        photo.capturePhoto(with: st, delegate: self)
        Haptic.tap(.medium)
    }

    func startVideo() {
        guard ready, !movie.isRecording else { return }
        if flash, let d = videoInput?.device, d.hasTorch, (try? d.lockForConfiguration()) != nil {
            d.torchMode = .on; d.unlockForConfiguration()
        }
        let u = FileManager.default.temporaryDirectory.appending(path: "story-\(UUID().uuidString).mov")
        movie.startRecording(to: u, recordingDelegate: self)
        started = Date()
        recording = true
        Haptic.tap(.heavy)
    }

    func stopVideo(_ done: @escaping (URL?) -> Void) {
        onMovie = done
        if movie.isRecording { movie.stopRecording() } else { done(nil) }
    }

    var elapsed: Double { started.map { Date().timeIntervalSince($0) } ?? 0 }

    func shutdown() {
        let s = session
        Task.detached { if s.isRunning { s.stopRunning() } }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto p: AVCapturePhoto, error: Error?) {
        let img = p.fileDataRepresentation().flatMap { UIImage(data: $0) }
        Task { @MainActor in
            onPhoto?(img); onPhoto = nil
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        MainActor.assumeIsolated {
            let light = EdgeLight.shared
            guard light.on, light.followFace else { return }
            guard let f = objects.first(where: { $0.type == .face }), let pl = previewLayer,
                  let t = pl.transformedMetadataObject(for: f) else {
                light.face = nil
                return
            }
            let r = pl.convert(t.bounds, to: nil)
            let sb = UIScreen.main.bounds
            guard sb.width > 0 else { return }
            light.face = CGRect(x: r.minX / sb.width, y: r.minY / sb.height, width: r.width / sb.width, height: r.height / sb.height)
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        let ok = (error == nil) || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        Task { @MainActor in
            recording = false
            started = nil
            if let d = videoInput?.device, d.hasTorch, d.torchMode == .on, (try? d.lockForConfiguration()) != nil {
                d.torchMode = .off; d.unlockForConfiguration()
            }
            onMovie?(ok ? url : nil); onMovie = nil
        }
    }
}

private struct StoryPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    final class V: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var pl: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> V { let v = V(); v.pl.session = session; v.pl.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ v: V, context: Context) {}
}

struct StoryCameraScreen: View {
    var onMedia: (StoryMedia) -> Void
    var onClose: () -> Void

    enum Mode: String, CaseIterable { case video, photo }

    @State private var cam = StoryCameraModel()
    @State private var mode: Mode = .photo
    @State private var thumb: UIImage?
    @State private var gallery = false
    @State private var pick: PhotosPickerItem?
    @State private var pressing = false
    @State private var holdTask: Task<Void, Never>?
    @State private var holdVideo = false
    @State private var flashFX = false
    @State private var zoomBase: CGFloat = 1
    @State private var loading = false
    @State private var light = EdgeLight.shared
    @State private var lightSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.06)
                if cam.ready { LitCameraPreview(cam: cam) }
                if cam.denied {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text("Нет доступа к камере").font(.headline)
                        Button("Открыть настройки") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                        .buttonStyle(.glass)
                    }
                    .foregroundStyle(.white)
                }
                if flashFX { Color.white.opacity(0.8).allowsHitTesting(false) }
                if loading { ProgressView().tint(.white).controlSize(.large) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .gesture(MagnifyGesture()
                .onChanged { v in cam.zoom(zoomBase * v.magnification) }
                .onEnded { _ in zoomBase = cam.zoomFactor })
            .onTapGesture(count: 2) { cam.flip() }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { shutter.padding(.bottom, 26) }
            .overlay(alignment: .top) {
                if cam.recording {
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        let s = Int(cam.elapsed)
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text(String(format: "%d:%02d", s / 60, s % 60)).font(.subheadline.monospacedDigit().bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.4), in: Capsule())
                    }
                    .padding(.top, 70)
                }
            }

            bottomBar
                .padding(.top, 14)
                .padding(.bottom, 6)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .task {
            await cam.prepare()
            thumb = await Self.lastPhoto()
        }
        .onDisappear {
            cam.shutdown()
            if light.on { light.forceOff() }
        }
        .overlay { if light.on { EdgeLightOverlay() } }
        .sheet(isPresented: $lightSettings) {
            EdgeLightControls()
                .padding(12)
                .presentationDetents([.height(470)])
                .presentationBackground(.clear)
        }
        .onChange(of: cam.front) { _, f in
            if f && light.autoFront && !light.on { withAnimation { light.acquire() } }
            if !f && light.autoFront && light.on { withAnimation { light.forceOff() } }
        }
        .task(id: light.on) {
            while light.on && !Task.isCancelled {
                light.updateAmbient(from: cam.device)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .photosPicker(isPresented: $gallery, selection: $pick, matching: .any(of: [.images, .videos]), preferredItemEncoding: .compatible)
        .onChange(of: pick) { _, it in if let it { Task { await load(it) } } }
    }

    // MARK: верх
    private var topBar: some View {
        HStack(spacing: 22) {
            // кольцевая подсветка экрана: нажатие — вкл/выкл, удержание — настройки
            Image(systemName: light.on ? "lightbulb.max.fill" : "lightbulb")
                .foregroundStyle(light.on ? EdgeLight.color(kelvin: light.effectiveKelvin) : .white)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.35)) { light.on ? light.forceOff() : light.acquire() }
                    Haptic.tap(.light)
                }
                .onLongPressGesture { lightSettings = true; Haptic.tap(.medium) }
                .accessibilityLabel("Кольцевая подсветка")
            Spacer()
            Button {
                cam.flash.toggle(); Haptic.tap(.light)
            } label: {
                Image(systemName: cam.flash ? "bolt.fill" : "bolt.slash.fill")
                    .foregroundStyle(cam.flash ? Color.yellow : .white)
            }
            Button { onClose() } label: { Image(systemName: "xmark") }
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 4)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .opacity(cam.recording ? 0 : 1)
    }

    // MARK: кнопка спуска
    private var shutter: some View {
        let recording = cam.recording
        let videoish = mode == .video || recording
        return ZStack {
            Circle()
                .stroke(.white.opacity(recording ? 0.35 : 0), lineWidth: 5)
                .frame(width: 92, height: 92)
            if recording {
                TimelineView(.animation) { _ in
                    Circle()
                        .trim(from: 0, to: min(1, cam.elapsed / 60))
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 92, height: 92)
                }
            }
            Circle()
                .fill(.black.opacity(0.25))
                .frame(width: 84, height: 84)
                .opacity(recording ? 0 : 1)
            RoundedRectangle(cornerRadius: recording && !holdVideo ? 8 : 40, style: .continuous)
                .fill(videoish ? Color.red : .white)
                .frame(width: recording ? (holdVideo ? 84 : 30) : 72, height: recording ? (holdVideo ? 84 : 30) : 72)
        }
        .scaleEffect(pressing && !recording ? 0.92 : 1)
        .animation(.spring(duration: 0.3), value: recording)
        .animation(.spring(duration: 0.2), value: pressing)
        .animation(.snappy, value: mode)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !pressing {
                        pressing = true
                        // в режиме ФОТО удержание включает видео
                        if mode == .photo && !cam.recording {
                            holdTask = Task {
                                try? await Task.sleep(for: .milliseconds(300))
                                if !Task.isCancelled && pressing { holdVideo = true; cam.startVideo() }
                            }
                        }
                    }
                    if holdVideo, cam.recording {
                        // тянем вверх — приближение, как в Telegram
                        let up = max(0, -v.translation.height)
                        cam.zoom(zoomBase * (1 + up / 120))
                    }
                }
                .onEnded { _ in
                    pressing = false
                    holdTask?.cancel()
                    if holdVideo {
                        holdVideo = false
                        zoomBase = cam.zoomFactor
                        finishVideo()
                        return
                    }
                    switch mode {
                    case .photo:
                        withAnimation(.easeOut(duration: 0.08)) { flashFX = true }
                        Task { try? await Task.sleep(for: .milliseconds(120)); withAnimation(.easeIn(duration: 0.2)) { flashFX = false } }
                        cam.shoot { img in if let img { onMedia(.photo(img)) } }
                    case .video:
                        if cam.recording { finishVideo() } else { cam.startVideo() }
                    }
                }
        )
        .onChange(of: cam.recording) { _, r in
            // остановилось само по лимиту 60 секунд
            if !r && holdVideo { holdVideo = false }
        }
    }

    private func finishVideo() {
        cam.stopVideo { url in
            if let url { onMedia(.video(url)) } else { OxAlert.error(String(localized: "Не удалось записать видео")) }
        }
    }

    // MARK: низ
    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button { gallery = true } label: {
                ZStack {
                    if let thumb {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Color(white: 0.2)
                        Image(systemName: "photo.on.rectangle").foregroundStyle(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .frame(width: 64)
            Spacer()
            HStack(spacing: 0) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Button {
                        guard !cam.recording else { return }
                        withAnimation(.snappy) { mode = m }
                        Haptic.tap(.light)
                    } label: {
                        Text(m == .video ? "ВИДЕО" : "ФОТО")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(mode == m ? Color.yellow : .white)
                            .padding(.horizontal, 20).frame(height: 40)
                            .background {
                                if mode == m { Capsule().fill(.black.opacity(0.55)) }
                            }
                    }
                }
            }
            .padding(4)
            .background(Color(white: 0.2), in: Capsule())
            .opacity(cam.recording ? 0.3 : 1)
            Spacer()
            Button { cam.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color(white: 0.2), in: Circle())
            }
            .frame(width: 64)
        }
        .padding(.horizontal, 10)
    }

    private func load(_ it: PhotosPickerItem) async {
        loading = true
        defer { loading = false; pick = nil }
        if it.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let mv = try? await it.loadTransferable(type: StoryMovie.self) { onMedia(.video(mv.url)) }
            else { OxAlert.error(String(localized: "Не удалось открыть видео")) }
        } else if let d = try? await it.loadTransferable(type: Data.self), let i = UIImage(data: d) {
            onMedia(.photo(i))
        } else {
            OxAlert.error(String(localized: "Не удалось открыть фото"))
        }
    }

    /// Последнее фото из галереи для кружка слева
    static func lastPhoto() async -> UIImage? {
        var st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if st == .notDetermined { st = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard st == .authorized || st == .limited else { return nil }
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 1
        guard let a = PHAsset.fetchAssets(with: o).firstObject else { return nil }
        return await withCheckedContinuation { c in
            let ro = PHImageRequestOptions()
            ro.deliveryMode = .highQualityFormat
            ro.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 140, height: 140), contentMode: .aspectFill, options: ro) { img, _ in
                c.resume(returning: img)
            }
        }
    }
}
