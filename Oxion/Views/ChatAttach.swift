import SwiftUI
import Photos
import MapKit
import CoreLocation

// MARK: - Вложения в чате как в Telegram: галерея с выбором по номерам, альбомы, карточки, геопозиция

@MainActor
@Observable
final class GalleryModel {
    struct Album: Identifiable, Hashable {
        let id: String
        let title: String
        let count: Int
        let collection: PHAssetCollection?
    }

    var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var assets: [PHAsset] = []
    var albums: [Album] = []
    var album: Album?
    var selected: [String] = []          // localIdentifier по порядку выбора
    let imageManager = PHCachingImageManager()

    func start() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }
        loadAlbums()
        load(album)
    }

    private func loadAlbums() {
        var out: [Album] = []
        let recents = imagesFetch(nil)
        out.append(Album(id: "recents", title: "Недавние", count: recents.count, collection: nil))
        let smart: [(PHAssetCollectionSubtype, String)] = [
            (.smartAlbumFavorites, "Избранное"), (.smartAlbumSelfPortraits, "Селфи"),
            (.smartAlbumScreenshots, "Снимки экрана"), (.smartAlbumLivePhotos, "Фото Live Photo"),
        ]
        for (sub, title) in smart {
            if let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil).firstObject {
                let n = imagesFetch(c).count
                if n > 0 { out.append(Album(id: c.localIdentifier, title: title, count: n, collection: c)) }
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
            let n = self.imagesFetch(c).count
            if n > 0 { out.append(Album(id: c.localIdentifier, title: c.localizedTitle ?? "Альбом", count: n, collection: c)) }
        }
        albums = out
        if album == nil { album = out.first }
    }

    private func imagesFetch(_ c: PHAssetCollection?) -> PHFetchResult<PHAsset> {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        o.fetchLimit = 900
        return c.map { PHAsset.fetchAssets(in: $0, options: o) } ?? PHAsset.fetchAssets(with: o)
    }

    func load(_ a: Album?) {
        let r = imagesFetch(a?.collection)
        var list: [PHAsset] = []
        list.reserveCapacity(r.count)
        r.enumerateObjects { a, _, _ in list.append(a) }
        assets = list
    }

    func toggle(_ a: PHAsset) {
        if let i = selected.firstIndex(of: a.localIdentifier) {
            selected.remove(at: i)
        } else if selected.count < 10 {
            selected.append(a.localIdentifier)
        } else {
            OxAlert.show(icon: "photo.stack", title: "Не больше 10 фото за раз")
            return
        }
        Haptic.tap()
    }

    func number(_ a: PHAsset) -> Int? {
        selected.firstIndex(of: a.localIdentifier).map { $0 + 1 }
    }

    /// Полноразмерная картинка для отправки
    func image(for id: String) async -> UIImage? {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .highQualityFormat
        o.version = .current
        return await withCheckedContinuation { c in
            PHImageManager.default().requestImageDataAndOrientation(for: a, options: o) { data, _, _, _ in
                c.resume(returning: data.flatMap { UIImage(data: $0) })
            }
        }
    }
}

struct ChatAttachSheet: View {
    let chatId: Int
    var replyTo: Int?
    var onSent: (Message) -> Void

    enum Tab: String, CaseIterable { case gallery, cards, location
        var title: String { switch self { case .gallery: "Галерея"; case .cards: "Карточки"; case .location: "Геопозиция" } }
        var icon: String { switch self { case .gallery: "photo.on.rectangle.angled"; case .cards: "rectangle.stack.fill"; case .location: "location.fill" } }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var g = GalleryModel()
    @State private var tab: Tab = .gallery
    @State private var caption = ""
    @State private var sending = false
    @State private var progress = 0
    @State private var camera = false
    @Namespace private var ns
    @FocusState private var captionFocus: Bool

    private var hasSelection: Bool { !g.selected.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .gallery: gallery
                    case .cards: AttachCardsList(chatId: chatId) { m in onSent(m); dismiss() }
                    case .location: LocationAttach(chatId: chatId) { m in onSent(m); dismiss() }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

                bottom
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: tab)
            .animation(.spring(duration: 0.42, bounce: 0.25), value: hasSelection)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                        if hasSelection {
                            Button {
                                withAnimation(.snappy) { g.selected.removeAll() }
                            } label: {
                                Label("\(g.selected.count)", systemImage: "checkmark")
                                    .font(.subheadline.bold())
                                    .contentTransition(.numericText())
                            }
                            .buttonStyle(.glassProminent)
                            .tint(Color.lime).foregroundStyle(.black)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if tab == .gallery {
                        Menu {
                            ForEach(g.albums) { a in
                                Button {
                                    g.album = a
                                    g.load(a)
                                } label: {
                                    Text(a.title)
                                    Text("\(a.count)")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(g.album?.title ?? "Недавние").font(.headline)
                                Image(systemName: "chevron.down").font(.caption.bold())
                            }
                            .foregroundStyle(.primary)
                        }
                    } else {
                        Text(tab.title).font(.headline)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
        .task { await g.start() }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in Task { await sendImages([img]) } }.ignoresSafeArea()
        }
    }

    // MARK: галерея

    @ViewBuilder private var gallery: some View {
        if g.status == .denied || g.status == .restricted {
            ContentUnavailableView {
                Label("Нет доступа к фото", systemImage: "photo")
            } description: {
                Text("Разрешите доступ: Настройки → Oxion → Фото")
            } actions: {
                Button("Открыть настройки") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .buttonStyle(.glassProminent)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    Button { camera = true } label: {
                        ZStack {
                            Color.black
                            Image(systemName: "camera.fill").font(.title).foregroundStyle(.white)
                        }
                        .aspectRatio(1, contentMode: .fill)
                    }
                    .buttonStyle(.plain)
                    ForEach(g.assets, id: \.localIdentifier) { a in
                        GalleryCell(asset: a, manager: g.imageManager, number: g.number(a)) {
                            withAnimation(.spring(duration: 0.3, bounce: 0.45)) { g.toggle(a) }
                        }
                    }
                }
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: низ: вкладки или подпись + отправка

    @ViewBuilder private var bottom: some View {
        if hasSelection && tab == .gallery {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Добавить подпись…", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($captionFocus)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                Button {
                    Task { await sendSelected(maxSide: 2000) }
                } label: {
                    ZStack {
                        if sending {
                            Text("\(progress)/\(g.selected.count)").font(.caption.bold().monospacedDigit())
                        } else {
                            Image(systemName: "arrow.up").font(.headline)
                        }
                    }
                    .frame(width: 46, height: 46)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Color.lime).foregroundStyle(.black)
                .disabled(sending)
                .contextMenu {
                    Button { Task { await sendSelected(maxSide: 4096) } } label: {
                        Label("Отправить в высоком качестве", systemImage: "4k.tv")
                    }
                    Button { Task { await sendSelected(maxSide: 2000, separate: true) } } label: {
                        Label("Подпись отдельным сообщением", systemImage: "text.bubble")
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            GlassEffectContainer {
                HStack(spacing: 2) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Button {
                            Haptic.tap()
                            tab = t
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: t.icon).font(.system(size: 19, weight: .semibold))
                                Text(t.title).font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(tab == t ? Color.lime : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                if tab == t {
                                    Capsule().fill(.white.opacity(0.1)).matchedGeometryEffect(id: "tab", in: ns)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { Haptic.tap(); camera = true } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "camera.fill").font(.system(size: 19, weight: .semibold))
                            Text("Камера").font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: отправка

    private func sendSelected(maxSide: CGFloat, separate: Bool = false) async {
        var imgs: [UIImage] = []
        for id in g.selected { if let i = await g.image(for: id) { imgs.append(i) } }
        await sendImages(imgs, maxSide: maxSide, separate: separate)
    }

    private func sendImages(_ imgs: [UIImage], maxSide: CGFloat = 2000, separate: Bool = false) async {
        guard !imgs.isEmpty else { return }
        sending = true
        progress = 0
        defer { sending = false }
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            for (i, img) in imgs.enumerated() {
                guard let jpg = API.jpeg(img, maxSide: maxSide) else { continue }
                var f: [String: String] = [:]
                if i == 0, let r = replyTo { f["reply_to"] = String(r) }
                if i == 0, !text.isEmpty, !separate { f["text"] = text }
                let m: Message = try await API.upload("/chats/\(chatId)/messages", fields: f, data: jpg)
                onSent(m)
                withAnimation(.snappy) { progress = i + 1 }
            }
            if separate, !text.isEmpty {
                let m: Message = try await API.call("/chats/\(chatId)/messages", method: "POST", body: ["text": text])
                onSent(m)
            }
            Haptic.success()
            dismiss()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

/// Ячейка галереи: миниатюра и кружок с номером выбора
private struct GalleryCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let number: Int?
    let toggle: () -> Void
    @State private var thumb: UIImage?

    var body: some View {
        Color.gray.opacity(0.15)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .overlay {
                if number != nil { Color.black.opacity(0.18) }
            }
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 1.6)
                        .background(Circle().fill(.black.opacity(0.15)))
                    if let number {
                        Circle().fill(Color.lime)
                        Text("\(number)").font(.caption.bold()).foregroundStyle(.black)
                            .contentTransition(.numericText())
                    }
                }
                .frame(width: 24, height: 24)
                .scaleEffect(number == nil ? 1 : 1.12)
                .padding(6)
            }
            .scaleEffect(number == nil ? 1 : 0.94)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .task(id: asset.localIdentifier) {
                let o = PHImageRequestOptions()
                o.deliveryMode = .opportunistic
                o.isNetworkAccessAllowed = true
                o.resizeMode = .fast
                manager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: o) { img, _ in
                    if let img { withAnimation(.easeOut(duration: 0.2)) { thumb = img } }
                }
            }
    }
}

/// Быстрые карточки: итоги недели, вес, тренировка, рекорд, прогресс
struct AttachCardsList: View {
    let chatId: Int
    var onSent: (Message) -> Void
    @State private var opts: AttachOptions?
    @State private var sending = false

    var body: some View {
        List {
            Section("Быстро") {
                row("chart.bar.fill", "Итоги недели", "Тренировки, подходы, серия") { await send(["kind": "week"]) }
                row("scalemass.fill", "Вес тела", "График веса") { await send(["kind": "weight"]) }
            }
            if let ws = opts?.workouts, !ws.isEmpty {
                Section("Тренировка") {
                    ForEach(ws) { w in
                        row("dumbbell.fill", w.title ?? "Тренировка", "\(RU.human(w.date)) · \(w.sets ?? 0) подх.") {
                            await send(["kind": "workout", "ref": w.id])
                        }
                    }
                }
            }
            if let ex = opts?.exercises, !ex.isEmpty {
                Section("Рекорды и прогресс") {
                    ForEach(ex) { e in
                        row("trophy.fill", e.name, "Лучший результат") { await send(["kind": "record", "ref": e.id]) }
                        row("chart.line.uptrend.xyaxis", e.name, "График за последние тренировки") { await send(["kind": "progress", "ref": e.id]) }
                    }
                }
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        .overlay { if sending { ProgressView() } }
        .task { opts = try? await API.call("/chats/\(chatId)/attach") }
    }

    private func row(_ icon: String, _ title: String, _ sub: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 12) {
                IconBubble(icon: icon, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary).lineLimit(1)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(sending)
    }

    private func send(_ body: [String: Any]) async {
        sending = true
        defer { sending = false }
        do {
            let m: Message = try await API.call("/chats/\(chatId)/messages", method: "POST", body: body)
            Haptic.success()
            onSent(m)
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

/// Отправка своей геопозиции ссылкой на Карты
struct LocationAttach: View {
    let chatId: Int
    var onSent: (Message) -> Void
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var loc = OneShotLocation()
    @State private var sending = false

    var body: some View {
        VStack(spacing: 12) {
            Map(position: $camera) { UserAnnotation() }
                .mapControls { MapUserLocationButton() }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, 12)
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.lime, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Отправить мою геопозицию").font(.headline)
                        Text(loc.coord == nil ? "Определяем…" : "Точность \(Int(loc.accuracy)) м").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if sending { ProgressView() }
                }
                .padding(12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            }
            .buttonStyle(.plain)
            .disabled(loc.coord == nil || sending)
            .padding(.horizontal, 12)
            .padding(.bottom, 90)
        }
        .onAppear { loc.request() }
    }

    private func send() async {
        guard let c = loc.coord else { return }
        sending = true
        defer { sending = false }
        let url = String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=%@", c.latitude, c.longitude, "Я здесь".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        do {
            let m: Message = try await API.call("/chats/\(chatId)/messages", method: "POST", body: ["text": "📍 Моя геопозиция\n\(url)"])
            Haptic.success()
            onSent(m)
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

@MainActor
@Observable
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    var coord: CLLocationCoordinate2D?
    var accuracy: Double = 0
    private let m = CLLocationManager()

    func request() {
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() }
        m.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            self.coord = l.coordinate
            self.accuracy = l.horizontalAccuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        if st == .authorizedWhenInUse || st == .authorizedAlways { manager.requestLocation() }
    }
}

/// Съёмка фото камерой
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
