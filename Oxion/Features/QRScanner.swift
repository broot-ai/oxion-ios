import SwiftUI
import AVFoundation
import PhotosUI
import CoreImage

// MARK: - Разбор QR-ссылок OXION

enum QRLinks {
    enum Result { case trainer(Int), user(Int), url(URL), text(String) }

    static func parse(_ code: String) -> Result {
        if let m = code.firstMatch(of: /(?:startapp=t|#trainer\/|\/clip\/trainer\/)(\d+)/), let id = Int(m.1) { return .trainer(id) }
        if let m = code.firstMatch(of: /(?:startapp=u|#u\/)(\d+)/), let id = Int(m.1) { return .user(id) }
        if let u = URL(string: code), let sc = u.scheme?.lowercased(), ["http", "https", "oxion"].contains(sc) { return .url(u) }
        return .text(code)
    }
}

// MARK: - Камера для QR (AVFoundation): своя рамка, фонарик, распознавание из фото

@MainActor
@Observable
final class QRCamera: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var denied = false
    var torch = false
    var found: CGRect?                       // где нашли код (в координатах превью)
    var onCode: ((String) -> Void)?
    weak var preview: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
    private var fired = false
    private var configured = false

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        case .denied, .restricted:
            denied = true; return
        default: break
        }
        if !configured { configure() }
        let s = session
        Task.detached { if !s.isRunning { s.startRunning() } }
    }

    func stop() {
        let s = session
        Task.detached { if s.isRunning { s.stopRunning() } }
    }

    private func configure() {
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: d), session.canAddInput(input) else {
            session.commitConfiguration(); return
        }
        device = d
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        if session.canAddOutput(out) {
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            out.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()
        if d.isFocusModeSupported(.continuousAutoFocus) {
            try? d.lockForConfiguration()
            d.focusMode = .continuousAutoFocus
            if d.isAutoFocusRangeRestrictionSupported { d.autoFocusRangeRestriction = .near }
            d.unlockForConfiguration()
        }
    }

    func toggleTorch() {
        guard let d = device, d.hasTorch else { return }
        try? d.lockForConfiguration()
        torch.toggle()
        d.torchMode = torch ? .on : .off
        d.unlockForConfiguration()
        Haptic.tap()
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject, let s = obj.stringValue else { return }
        MainActor.assumeIsolated { self.detected(obj, s) }
    }

    private func detected(_ obj: AVMetadataMachineReadableCodeObject, _ s: String) {
        guard !fired else { return }
        fired = true
        if let t = preview?.transformedMetadataObject(for: obj) { found = t.bounds.insetBy(dx: -14, dy: -14) }
        OxHaptics.play(.setDone)
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if torch { toggleTorch() }
            stop()
            onCode?(s)
        }
    }

    /// QR с картинки из галереи
    func scan(image: UIImage) {
        guard let ci = CIImage(image: image),
              let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
              let f = det.features(in: ci).compactMap({ $0 as? CIQRCodeFeature }).first,
              let s = f.messageString else {
            OxAlert.show(icon: "qrcode", tint: .orange, title: "QR-код не найден", message: "На этом фото нет QR-кода или он слишком мелкий.")
            return
        }
        fired = true
        OxHaptics.play(.setDone)
        stop()
        onCode?(s)
    }
}

private final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct QRCameraPreview: UIViewRepresentable {
    let cam: QRCamera
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = cam.session
        v.previewLayer.videoGravity = .resizeAspectFill
        cam.preview = v.previewLayer
        return v
    }
    func updateUIView(_ v: PreviewUIView, context: Context) {}
}

/// Уголки рамки сканера
struct ScanCorners: Shape {
    var len: CGFloat = 34
    var radius: CGFloat = 26

    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = min(len, r.width / 2), rr = min(radius, l)
        // левый верх
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rr))
        p.addQuadCurve(to: CGPoint(x: r.minX + rr, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // правый верх
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rr, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + rr), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // правый низ
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rr))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rr, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // левый низ
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rr, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rr), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

struct QRScanScreen: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cam = QRCamera()
    @State private var pick: PhotosPickerItem?
    @State private var scanPhase = false
    @State private var appear = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width * 0.68, 290)
            let idle = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2 - 40, width: side, height: side)
            let frame = cam.found ?? idle
            ZStack {
                Color.black
                if !cam.denied {
                    QRCameraPreview(cam: cam)
                        .opacity(appear ? 1 : 0)
                }
                // затемнение с «окном»
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .allowsHitTesting(false)

                ScanCorners()
                    .stroke(cam.found == nil ? Color.white : Color.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .shadow(color: (cam.found == nil ? Color.white : Color.lime).opacity(0.5), radius: 8)
                    .scaleEffect(appear ? 1 : 1.25)

                if cam.found == nil && !cam.denied {
                    // бегущая линия
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, Color.lime, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: idle.width - 40, height: 3)
                        .shadow(color: Color.lime, radius: 6)
                        .position(x: idle.midX, y: scanPhase ? idle.maxY - 22 : idle.minY + 22)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: scanPhase)
                }

                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.headline).frame(width: 46, height: 46)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        Spacer()
                        Text("Сканер QR").font(.headline)
                        Spacer()
                        Color.clear.frame(width: 46, height: 46)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, geo.safeAreaInsets.top + 6)

                    Spacer()

                    Text(cam.denied ? "Нет доступа к камере" : cam.found == nil ? "Наведите камеру на QR-код" : "Нашли!")
                        .font(.subheadline.bold())
                        .contentTransition(.opacity)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 26)

                    HStack(spacing: 40) {
                        PhotosPicker(selection: $pick, matching: .images) {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle").font(.title3).frame(width: 60, height: 60)
                                    .glassEffect(.regular.interactive(), in: .circle)
                                Text("Из фото").font(.caption.bold())
                            }
                        }
                        .buttonStyle(.plain)
                        Button { cam.toggleTorch() } label: {
                            VStack(spacing: 6) {
                                Image(systemName: cam.torch ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.title3)
                                    .foregroundStyle(cam.torch ? .black : .white)
                                    .frame(width: 60, height: 60)
                                    .background(cam.torch ? Color.white : .clear, in: Circle())
                                    .glassEffect(.regular.interactive(), in: .circle)
                                    .contentTransition(.symbolEffect(.replace))
                                Text("Фонарик").font(.caption.bold())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom + 24)
                }
                .foregroundStyle(.white)

                if cam.denied {
                    VStack(spacing: 14) {
                        Image(systemName: "camera.fill").font(.system(size: 44))
                        Text("Разрешите доступ к камере, чтобы сканировать QR-коды").multilineTextAlignment(.center)
                        Button("Открыть настройки") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .foregroundStyle(.white)
                    .padding(40)
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.3), value: cam.found)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .task {
            cam.onCode = { code in onCode(code) }
            await cam.start()
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appear = true }
            scanPhase = true
        }
        .onDisappear { cam.stop() }
        .onChange(of: pick) {
            guard let pick else { return }
            Task {
                if let d = try? await pick.loadTransferable(type: Data.self), let img = UIImage(data: d) { cam.scan(image: img) }
                self.pick = nil
            }
        }
    }
}
