import SwiftUI
import MapKit
import CoreLocation

// Карта Oxion: только спортивные места (залы, стадионы, бассейны, корты…) из Apple Maps
// и магазины спортпита, зарегистрированные в Oxion. Точку магазина добавляет владелец, подтверждает платформа.

// MARK: - Модели

struct MapShopPlace: Decodable, Identifiable, Hashable {
    let id: Int
    let storeId: Int
    let name: String
    let tagline: String?
    let logo: String?
    let address: String
    let lat: Double
    let lng: Double
    let hours: String?
    let phone: String?
    let site: String?
    let status: String?
    let rejectReason: String?
    let rating: Double?
    let ratingCount: Int?
    let owner: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}

struct MapShopsResponse: Decodable { let items: [MapShopPlace] }
struct MapMyStore: Decodable, Identifiable, Hashable { let id: Int; let name: String; let logo: String?; let active: Bool? }
struct MapMyResponse: Decodable { let stores: [MapMyStore]; let places: [MapShopPlace] }

enum SportCategory: String, CaseIterable, Identifiable {
    case all, gym, stadium, pool, courts, shop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Все"
        case .gym: "Залы"
        case .stadium: "Стадионы"
        case .pool: "Бассейны"
        case .courts: "Площадки"
        case .shop: "Спортпит"
        }
    }
    var icon: String {
        switch self {
        case .all: "sportscourt"
        case .gym: "dumbbell.fill"
        case .stadium: "sportscourt.fill"
        case .pool: "figure.pool.swim"
        case .courts: "tennisball.fill"
        case .shop: "bag.fill"
        }
    }
    var poi: [MKPointOfInterestCategory] {
        switch self {
        case .all: SportMapView.sportPOI
        case .gym: [.fitnessCenter, .rockClimbing]
        case .stadium: [.stadium, .skating]
        case .pool: [.swimming]
        case .courts: [.tennis, .soccer, .basketball, .volleyball, .skatePark, .golf, .bowling]
        case .shop: []
        }
    }
    static func of(_ c: MKPointOfInterestCategory?) -> (String, String) {
        guard let c else { return ("Спорт", "sportscourt.fill") }
        switch c {
        case .fitnessCenter: return ("Фитнес-клуб", "dumbbell.fill")
        case .stadium: return ("Стадион", "sportscourt.fill")
        case .swimming: return ("Бассейн", "figure.pool.swim")
        case .tennis: return ("Теннис", "tennisball.fill")
        case .soccer: return ("Футбол", "soccerball")
        case .basketball: return ("Баскетбол", "basketball.fill")
        case .volleyball: return ("Волейбол", "volleyball.fill")
        case .skating: return ("Каток", "figure.skating")
        case .skiing: return ("Лыжи", "figure.skiing.downhill")
        case .rockClimbing: return ("Скалодром", "figure.climbing")
        case .skatePark: return ("Скейт-парк", "skateboard")
        case .golf: return ("Гольф", "figure.golf")
        case .bowling: return ("Боулинг", "figure.bowling")
        default: return ("Спорт", "sportscourt.fill")
        }
    }
}

@MainActor @Observable
final class MapLocator: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var location: CLLocation?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        Task { @MainActor in self.location = l }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in self.manager.startUpdatingLocation() }
    }
}

// MARK: - Экран карты

struct SportMapView: View {
    static let sportPOI: [MKPointOfInterestCategory] = [.fitnessCenter, .stadium, .swimming, .tennis, .soccer, .basketball,
                                                        .volleyball, .skating, .skiing, .rockClimbing, .skatePark, .golf, .bowling]

    @Environment(AppModel.self) private var model
    @Namespace private var mapScope
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var region: MKCoordinateRegion?
    @State private var selection: MapSelection<String>?
    @State private var category: SportCategory = .all
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var shops: [MapShopPlace] = []
    @State private var searching = false
    @State private var picked: MKMapItem?
    @State private var pickedShop: MapShopPlace?
    @State private var detent: PresentationDetent = .height(250)
    @State private var showPanel = true
    @State private var my: MapMyResponse?
    @State private var addShop = false
    @State private var openStore: Int?
    @State private var locator = MapLocator()
    @State private var locIntro = false
    @State private var movedSinceSearch = false
    @FocusState private var searchFocused: Bool

    private var shownShops: [MapShopPlace] {
        guard category == .all || category == .shop else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? shops : shops.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.address.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Map(position: $position, selection: $selection, scope: mapScope) {
            UserAnnotation()
            ForEach(Array(results.enumerated()), id: \.offset) { i, it in
                let meta = SportCategory.of(it.pointOfInterestCategory)
                Marker(it.name ?? meta.0, systemImage: meta.1, coordinate: it.placemark.coordinate)
                    .tint(Color(hex: 0x3FD6C9))
                    .tag(MapSelection("g\(i)"))
            }
            ForEach(shownShops) { s in
                Annotation(s.name, coordinate: s.coordinate) {
                    ShopPin(logo: s.logo, selected: pickedShop?.id == s.id)
                }
                .tag(MapSelection("s\(s.id)"))
            }
        }
        // на карте — только спортивные места Apple Maps
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including(category == .shop ? [] : category.poi)))
        .mapFeatureSelectionDisabled { f in
            guard let c = f.pointOfInterestCategory else { return true }
            return !Self.sportPOI.contains(c)
        }
        .mapControls { }
        .mapScope(mapScope)
        // карта под статус-баром, а кнопки — ниже «острова»
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.leading, 14).padding(.top, 6)
        }
        .overlay(alignment: .topTrailing) {
            // одна стеклянная «таблетка» с кнопками, как в Картах Apple
            VStack(spacing: 0) {
                Button {
                    withAnimation(.smooth(duration: 0.5)) { position = .userLocation(fallback: .automatic) }
                    Haptic.tap(.soft)
                } label: {
                    Image(systemName: position.followsUserLocation ? "location.fill" : "location")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.limeInk)
                        .frame(width: 46, height: 46)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Моё местоположение")
                if my?.stores.isEmpty == false {
                    Divider().frame(width: 26)
                    Button { addShop = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.limeInk)
                            .frame(width: 46, height: 46)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Добавить магазин на карту")
                }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.trailing, 14).padding(.top, 6)
        }
        .overlay(alignment: .top) {
            if movedSinceSearch && category != .shop && picked == nil && pickedShop == nil {
                Button { Task { await search() } } label: {
                    Label("Искать здесь", systemImage: "magnifyingglass").font(.subheadline.bold()).padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            let first = region == nil
            region = ctx.region
            if first { Task { await search() } } else { withAnimation(.smooth) { movedSinceSearch = true } }
        }
        .onChange(of: selection) { Task { await resolveSelection() } }
        .sheet(isPresented: $showPanel) {
            panel
                .presentationDetents([.height(90), .height(250), .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(250)))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .sheet(isPresented: $locIntro) {
                    OxIntroSheet(intro: .location, primary: "Показать рядом со мной",
                                 onContinue: { locIntro = false; locator.start() },
                                 onLater: { locIntro = false })
                }
                .sheet(isPresented: $addShop) {
                    AddShopPlaceSheet(stores: my?.stores ?? [], center: region?.center ?? locator.location?.coordinate) { _ in
                        Task { await loadMy() }
                    }
                }
                .sheet(item: Binding(get: { openStore.map { AppModel.IdBox(id: $0) } }, set: { openStore = $0?.id })) { b in
                    NavigationStack { StorePageView(storeId: b.id) }
                }
        }
        .task {
            if locator.manager.authorizationStatus == .notDetermined && !OxIntro.location.seen {
                locIntro = true
            } else {
                locator.start()
            }
            await loadShops()
            await loadMy()
        }
    }

    // MARK: панель снизу (как в Картах Apple)

    @ViewBuilder
    private var panel: some View {
        if let s = pickedShop {
            ShopPlaceCard(place: s, from: locator.location) { openStore = s.storeId } onClose: { clearPick() }
        } else if let it = picked {
            SportPlaceCard(item: it, from: locator.location) { clearPick() }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Спортзал, бассейн, магазин", text: $query)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        if !query.isEmpty {
                            Button { query = ""; Task { await search() } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .onChange(of: searchFocused) { if searchFocused { detent = .large } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SportCategory.allCases) { c in
                            Button {
                                withAnimation(.smooth(duration: 0.25)) { category = c }
                                Haptic.tap(.soft)
                                Task { await search() }
                            } label: {
                                Label(c.title, systemImage: c.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .foregroundStyle(category == c ? Color.onLime : Color.primary)
                                    .background(category == c ? Color.lime : Color.primary.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                List {
                    if searching && results.isEmpty && shownShops.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                    }
                    if !shownShops.isEmpty {
                        Section("Спортпит в Oxion") {
                            ForEach(shownShops) { s in
                                Button { select(shop: s) } label: { shopRow(s) }
                            }
                        }
                    }
                    if category != .shop {
                        Section(results.isEmpty ? "" : "Спортивные места") {
                            ForEach(Array(results.enumerated()), id: \.offset) { i, it in
                                Button { selection = MapSelection("g\(i)") } label: { placeRow(it) }
                            }
                        }
                    }
                    if !searching && results.isEmpty && shownShops.isEmpty {
                        Text(category == .shop ? "Магазинов спортпита Oxion рядом пока нет" : "Ничего не нашлось — подвиньте карту и нажмите «Искать здесь»")
                            .font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
                    }
                    if let my, !my.places.isEmpty {
                        Section("Мои точки на карте") {
                            ForEach(my.places) { p in myPlaceRow(p) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func placeRow(_ it: MKMapItem) -> some View {
        let meta = SportCategory.of(it.pointOfInterestCategory)
        return HStack(spacing: 12) {
            Image(systemName: meta.1).font(.subheadline).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Color(hex: 0x3FD6C9), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(it.name ?? meta.0).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text([meta.0, distance(it.placemark.coordinate)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func shopRow(_ s: MapShopPlace) -> some View {
        HStack(spacing: 12) {
            ShopPin(logo: s.logo, selected: false).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(["Спортпит", distance(s.coordinate), s.address].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let r = s.rating, r > 0 {
                Label(String(format: "%.1f", r), systemImage: "star.fill").font(.caption.bold()).foregroundStyle(.orange)
            }
        }
    }

    private func myPlaceRow(_ p: MapShopPlace) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.subheadline.weight(.semibold))
                Text(p.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if p.status == "rejected", let r = p.rejectReason { Text("Причина: \(r)").font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            Text(p.status == "approved" ? "На карте" : p.status == "rejected" ? "Отклонено" : "На проверке")
                .font(.caption.bold())
                .foregroundStyle(p.status == "approved" ? Color.limeInk : p.status == "rejected" ? .red : .orange)
        }
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    let _: OK? = try? await API.call("/m/map/places/\(p.id)", method: "DELETE")
                    await loadMy(); await loadShops()
                }
            } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    // MARK: логика

    private func distance(_ c: CLLocationCoordinate2D) -> String? {
        guard let me = locator.location else { return nil }
        let d = me.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return d < 1000 ? "\(Int(d)) м" : String(format: "%.1f км", d / 1000)
    }

    /// закрыть карту: сначала убираем нижнюю панель, потом сам экран
    private func close() {
        Haptic.tap(.soft)
        showPanel = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { model.showMap = false }
    }

    private func select(shop s: MapShopPlace) {
        selection = MapSelection("s\(s.id)")
    }

    private func clearPick() {
        withAnimation(.smooth(duration: 0.3)) {
            selection = nil
            picked = nil
            pickedShop = nil
            detent = .height(250)
        }
    }

    private func resolveSelection() async {
        guard let sel = selection else {
            withAnimation(.smooth(duration: 0.3)) { picked = nil; pickedShop = nil }
            return
        }
        Haptic.tap(.soft)
        if let f = sel.feature {
            // встроенная точка Apple Maps (зал, стадион…)
            if let it = try? await MKMapItemRequest(feature: f).mapItem {
                withAnimation(.smooth(duration: 0.3)) { pickedShop = nil; picked = it; detent = .height(250) }
            }
            return
        }
        guard let v = sel.value else { return }
        if v.hasPrefix("s"), let id = Int(v.dropFirst()), let s = shops.first(where: { $0.id == id }) {
            withAnimation(.smooth(duration: 0.3)) { picked = nil; pickedShop = s; detent = .height(250) }
            position = .camera(MapCamera(centerCoordinate: s.coordinate, distance: 1500))
        } else if v.hasPrefix("g"), let i = Int(v.dropFirst()), results.indices.contains(i) {
            let it = results[i]
            withAnimation(.smooth(duration: 0.3)) { pickedShop = nil; picked = it; detent = .height(250) }
            position = .camera(MapCamera(centerCoordinate: it.placemark.coordinate, distance: 1500))
        }
    }

    private func search() async {
        withAnimation(.smooth) { movedSinceSearch = false }
        guard category != .shop else { results = []; return }
        let reg = region ?? MKCoordinateRegion(center: locator.location?.coordinate ?? CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
                                                latitudinalMeters: 6000, longitudinalMeters: 6000)
        searching = true
        defer { searching = false }
        let q = query.trimmingCharacters(in: .whitespaces)
        var items: [MKMapItem] = []
        if q.isEmpty {
            let r = MKLocalPointsOfInterestRequest(coordinateRegion: reg)
            r.pointOfInterestFilter = MKPointOfInterestFilter(including: category.poi)
            items = (try? await MKLocalSearch(request: r).start().mapItems) ?? []
            // POI-запрос отдаёт немного мест — добиваем обычным поиском
            if items.count < 8 {
                let r2 = MKLocalSearch.Request()
                r2.naturalLanguageQuery = category == .pool ? "бассейн" : category == .stadium ? "стадион" : category == .courts ? "спортивная площадка" : "спортзал"
                r2.region = reg
                r2.resultTypes = .pointOfInterest
                r2.pointOfInterestFilter = MKPointOfInterestFilter(including: category.poi)
                items += (try? await MKLocalSearch(request: r2).start().mapItems) ?? []
            }
        } else {
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = q
            r.region = reg
            r.resultTypes = .pointOfInterest
            r.pointOfInterestFilter = MKPointOfInterestFilter(including: category.poi)
            items = (try? await MKLocalSearch(request: r).start().mapItems) ?? []
        }
        // без дублей и только спорт
        var seen = Set<String>()
        let clean = items.filter { it in
            guard let c = it.pointOfInterestCategory, Self.sportPOI.contains(c) else { return false }
            let k = "\(it.name ?? "")|\(Int(it.placemark.coordinate.latitude * 1e4))|\(Int(it.placemark.coordinate.longitude * 1e4))"
            return seen.insert(k).inserted
        }
        withAnimation(.smooth(duration: 0.3)) { results = Array(clean.prefix(60)) }
    }

    private func loadShops() async {
        if let r: MapShopsResponse = try? await API.call("/m/map/places") { withAnimation { shops = r.items } }
    }

    private func loadMy() async {
        my = try? await API.call("/m/map/my")
    }
}

// MARK: - Пин магазина

struct ShopPin: View {
    let logo: String?
    var selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(Color.lime)
            if let u = API.media(logo) {
                RemoteImage(url: u).clipShape(Circle()).padding(3)
            } else {
                Image(systemName: "bag.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.onLime)
            }
        }
        .frame(width: selected ? 46 : 34, height: selected ? 46 : 34)
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .animation(.spring(duration: 0.3), value: selected)
    }
}

// MARK: - Кнопки действий, как в Картах

private struct ActionButton: View {
    let title: String
    let icon: String
    var primary = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(primary ? Color.onLime : Color.limeInk)
            .background(primary ? Color.lime : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private func etaText(_ s: TimeInterval) -> String {
    let m = Int(s / 60)
    return m < 60 ? "\(max(1, m)) мин" : "\(m / 60) ч \(m % 60) мин"
}

private func openDirections(to item: MKMapItem) {
    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
}

private func call(_ phone: String?) {
    guard let p = phone?.filter({ $0.isNumber || $0 == "+" }), !p.isEmpty, let u = URL(string: "tel:\(p)") else { return }
    UIApplication.shared.open(u)
}

// MARK: - Карточка спортивного места

struct SportPlaceCard: View {
    let item: MKMapItem
    let from: CLLocation?
    var onClose: () -> Void
    @State private var eta: TimeInterval?

    var body: some View {
        let meta = SportCategory.of(item.pointOfInterestCategory)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? meta.0).font(.title2.bold())
                        Text(meta.0).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").font(.subheadline.bold()).frame(width: 32, height: 32) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                }
                HStack(spacing: 8) {
                    ActionButton(title: eta.map(etaText) ?? "Маршрут", icon: "car.fill", primary: true) { openDirections(to: item) }
                    if item.phoneNumber != nil { ActionButton(title: "Вызов", icon: "phone.fill") { call(item.phoneNumber) } }
                    if let u = item.url { ActionButton(title: "Веб-сайт", icon: "safari.fill") { UIApplication.shared.open(u) } }
                }
                if let d = distanceText {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Расстояние").font(.caption).foregroundStyle(.secondary)
                            Label(d, systemImage: "location.north.fill").font(.subheadline.bold())
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Подробно").font(.headline).padding(.bottom, 8)
                    if let p = item.phoneNumber { infoRow("Телефон", p) { call(p) } }
                    if let u = item.url { infoRow("Сайт", u.host() ?? u.absoluteString) { UIApplication.shared.open(u) } }
                    infoRow("Адрес", address, link: false) {}
                }
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button { item.openInMaps() } label: { Label("Открыть в Картах", systemImage: "map") }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(18)
        }
        .task(id: item) { await loadETA() }
    }

    private var address: String {
        let p = item.placemark
        return [p.thoroughfare.map { $0 + (p.subThoroughfare.map { ", " + $0 } ?? "") }, p.locality, p.administrativeArea]
            .compactMap { $0 }.joined(separator: "\n")
    }

    private var distanceText: String? {
        guard let from else { return nil }
        let c = item.placemark.coordinate
        let d = from.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return d < 1000 ? "\(Int(d)) м" : String(format: "%.1f км", d / 1000)
    }

    private func loadETA() async {
        let r = MKDirections.Request()
        r.source = .forCurrentLocation()
        r.destination = item
        r.transportType = .automobile
        eta = try? await MKDirections(request: r).calculateETA().expectedTravelTime
    }

    private func infoRow(_ t: String, _ v: String, link: Bool = true, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.caption).foregroundStyle(.secondary)
                Text(v).font(.subheadline).foregroundStyle(link ? Color.limeInk : Color.primary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(!link)
    }
}

// MARK: - Карточка магазина Oxion

struct ShopPlaceCard: View {
    let place: MapShopPlace
    let from: CLLocation?
    var onOpen: () -> Void
    var onClose: () -> Void
    @State private var eta: TimeInterval?

    private var mapItem: MKMapItem {
        let it = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        it.name = place.name
        return it
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ShopPin(logo: place.logo, selected: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.title2.bold())
                        HStack(spacing: 6) {
                            Text("Спортпит · магазин Oxion").font(.subheadline).foregroundStyle(.secondary)
                            if let r = place.rating, r > 0 {
                                Label(String(format: "%.1f", r), systemImage: "star.fill").font(.caption.bold()).foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").font(.subheadline.bold()).frame(width: 32, height: 32) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                }
                HStack(spacing: 8) {
                    ActionButton(title: "Магазин", icon: "bag.fill", primary: true, action: onOpen)
                    ActionButton(title: eta.map(etaText) ?? "Маршрут", icon: "car.fill") { openDirections(to: mapItem) }
                    if let p = place.phone, !p.isEmpty { ActionButton(title: "Вызов", icon: "phone.fill") { call(p) } }
                }
                if let t = place.tagline, !t.isEmpty { Text(t).font(.subheadline) }
                VStack(alignment: .leading, spacing: 10) {
                    if let h = place.hours, !h.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Часы работы").font(.caption).foregroundStyle(.secondary)
                            Text(h).font(.subheadline)
                        }
                    }
                    if let p = place.phone, !p.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Телефон").font(.caption).foregroundStyle(.secondary)
                            Button(p) { call(p) }.font(.subheadline).foregroundStyle(Color.limeInk)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Адрес").font(.caption).foregroundStyle(.secondary)
                        Text(place.address).font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(18)
        }
        .task(id: place.id) {
            let r = MKDirections.Request()
            r.source = .forCurrentLocation()
            r.destination = mapItem
            eta = try? await MKDirections(request: r).calculateETA().expectedTravelTime
        }
    }
}

// MARK: - Страница магазина

struct StoreInfo: Decodable {
    let id: Int
    let name: String
    let description: String?
    let tagline: String?
    let city: String?
    let logo: String?
    let cover: String?
    let rating: Double?
    let ratingCount: Int?
    let ordersDone: Int?
    let pickup: Bool?
    let delivery: Bool?
}

struct StorePageView: View {
    let storeId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var store: StoreInfo?
    @State private var items: [MProduct] = []
    @State private var error: String?
    @State private var openProduct: Int?

    var body: some View {
        ScrollView {
            if let s = store {
                VStack(alignment: .leading, spacing: 14) {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(url: API.media(s.cover))
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        RemoteImage(url: API.media(s.logo))
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.oxBg, lineWidth: 3))
                            .offset(x: 14, y: 30)
                    }
                    .padding(.bottom, 26)
                    Text(s.name).font(.title.bold())
                    if let t = s.tagline, !t.isEmpty { Text(t).foregroundStyle(.secondary) }
                    HStack(spacing: 14) {
                        if let r = s.rating, r > 0 { Label(String(format: "%.1f (%d)", r, s.ratingCount ?? 0), systemImage: "star.fill").foregroundStyle(.orange) }
                        if let n = s.ordersDone, n > 0 { Label("\(n) заказов", systemImage: "shippingbox.fill").foregroundStyle(.secondary) }
                        if s.pickup == true { Label("Самовывоз", systemImage: "figure.walk").foregroundStyle(.secondary) }
                    }
                    .font(.caption.bold())
                    if let d = s.description, !d.isEmpty { Text(d).font(.subheadline) }
                    Text("Товары").font(.title3.bold()).padding(.top, 6)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(items) { p in ProductTile(p: p) { openProduct = p.id } }
                    }
                    if items.isEmpty { Text("Товаров пока нет").foregroundStyle(.secondary) }
                }
                .padding(16)
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }.padding(.top, 60)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Color.oxBg)
        .navigationTitle(store?.name ?? "Магазин")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        .sheet(item: Binding(get: { openProduct.map { AppModel.IdBox(id: $0) } }, set: { openProduct = $0?.id })) { b in
            NavigationStack { ProductView(productId: b.id, onCart: { _ in }) }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            store = try await API.call("/m/stores/\(storeId)")
            if let r: MCatalog = try? await API.call("/m/products", query: ["store": String(storeId)]) { items = r.items }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Владелец: добавить магазин на карту

struct AddShopPlaceSheet: View {
    let stores: [MapMyStore]
    let center: CLLocationCoordinate2D?
    var onDone: (MapShopPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var storeId: Int?
    @State private var position: MapCameraPosition = .automatic
    @State private var point: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var hours = ""
    @State private var phone = ""
    @State private var site = ""
    @State private var sending = false
    @State private var geocoding = false

    private var activeStores: [MapMyStore] { stores.filter { $0.active == true } }

    var body: some View {
        NavigationStack {
            Form {
                if activeStores.isEmpty {
                    Section {
                        Text("Добавить точку можно после того, как ваш магазин пройдёт проверку в Oxion.").foregroundStyle(.secondary)
                    }
                } else {
                    if activeStores.count > 1 {
                        Picker("Магазин", selection: $storeId) {
                            ForEach(activeStores) { s in Text(s.name).tag(Optional(s.id)) }
                        }
                    }
                    Section {
                        // двигайте карту — точка магазина в центре
                        Map(position: $position) { UserAnnotation() }
                            .mapStyle(.standard(pointsOfInterest: .excludingAll))
                            .frame(height: 240)
                            .overlay {
                                Image(systemName: "mappin")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(Color.lime, Color.black)
                                    .offset(y: -16)
                                    .shadow(radius: 3)
                                    .allowsHitTesting(false)
                            }
                            .onMapCameraChange(frequency: .onEnd) { ctx in
                                point = ctx.region.center
                                Task { await geocode(ctx.region.center) }
                            }
                            .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Передвиньте карту так, чтобы булавка стояла на входе в магазин.")
                    }
                    Section("Адрес") {
                        HStack {
                            TextField("Улица, дом", text: $address, axis: .vertical)
                            if geocoding { ProgressView() }
                        }
                    }
                    Section("Подробно") {
                        TextField("Часы работы, например 10:00–21:00", text: $hours)
                        TextField("Телефон", text: $phone).keyboardType(.phonePad)
                        TextField("Сайт", text: $site).keyboardType(.URL).textInputAutocapitalization(.never)
                    }
                    Section {
                        Text("После отправки точку проверит администрация Oxion. Пока идёт проверка, её видите только вы.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Магазин на карте")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") { Task { await send() } }
                        .bold()
                        .disabled(sending || storeId == nil || point == nil || address.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
            .onAppear {
                storeId = activeStores.first?.id
                if let c = center {
                    position = .camera(MapCamera(centerCoordinate: c, distance: 800))
                    point = c
                    Task { await geocode(c) }
                } else {
                    position = .userLocation(fallback: .automatic)
                }
            }
        }
    }

    private func geocode(_ c: CLLocationCoordinate2D) async {
        geocoding = true
        defer { geocoding = false }
        guard let pm = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude),
                                                                      preferredLocale: L10n.locale).first else { return }
        let line = [pm.thoroughfare.map { $0 + (pm.subThoroughfare.map { ", " + $0 } ?? "") }, pm.locality].compactMap { $0 }.joined(separator: ", ")
        if !line.isEmpty { address = line }
    }

    private func send() async {
        guard let storeId, let p = point else { return }
        sending = true
        defer { sending = false }
        do {
            let r: MapShopPlace = try await API.call("/m/map/places", method: "POST", body: [
                "store_id": storeId, "lat": p.latitude, "lng": p.longitude, "address": address,
                "hours": hours, "phone": phone, "site": site])
            Haptic.success()
            OxAlert.show(icon: "checkmark.seal.fill", title: "Заявка отправлена", message: "Точка появится на карте после проверки администрацией")
            onDone(r)
            dismiss()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - Панель платформы: модерация точек

struct MapPlacesAdminView: View {
    @State private var status = "pending"
    @State private var items: [MapShopPlace] = []
    @State private var loading = false
    @State private var rejecting: MapShopPlace?
    @Namespace private var tabNS

    private let tabs: [(String, String, String)] = [("pending", "На проверке", "clock"), ("approved", "Одобрены", "checkmark.seal"), ("rejected", "Отклонены", "xmark.seal")]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // вкладки-капсулы
                HStack(spacing: 6) {
                    ForEach(tabs, id: \.0) { t in
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { status = t.0 }
                            Haptic.tap(.soft)
                        } label: {
                            Label(t.1, systemImage: t.2)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(status == t.0 ? Color.onLime : Color.primary.opacity(0.75))
                                .background {
                                    if status == t.0 { Capsule().fill(Color.lime).matchedGeometryEffect(id: "tab", in: tabNS) }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.oxCard, in: Capsule())

                if loading && items.isEmpty {
                    ProgressView().padding(.top, 60)
                } else if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: status == "pending" ? "tray" : "map").font(.system(size: 40)).foregroundStyle(Color.oxHint)
                        Text(status == "pending" ? "Новых заявок нет" : "Пусто").font(.headline)
                        Text(status == "pending" ? "Когда владелец магазина добавит точку на карту, она появится здесь" : "")
                            .font(.subheadline).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                    .padding(.horizontal, 30)
                }
                ForEach(items) { p in card(p).transition(.opacity.combined(with: .scale(scale: 0.97))) }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Магазины на карте")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: status) { await load() }
        .oxRefreshable { await load() }
        .sheet(item: $rejecting) { p in
            RejectPlaceSheet(place: p) { reason in Task { await decide(p, false, reason: reason) } }
        }
    }

    private func card(_ p: MapShopPlace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: p.coordinate, distance: 600)), interactionModes: [.zoom, .pan]) {
                Annotation(p.name, coordinate: p.coordinate) { ShopPin(logo: p.logo, selected: true) }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 190)
            .overlay(alignment: .topLeading) {
                Text(statusTitle(p.status))
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(p.status == "approved" ? Color.onLime : .white)
                    .background(statusColor(p.status), in: Capsule())
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    RemoteImage(url: API.media(p.logo), icon: "bag.fill")
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.title3.bold()).lineLimit(1)
                        Label(p.owner ?? "Владелец", systemImage: "person.crop.circle").font(.caption).foregroundStyle(Color.oxHint)
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("mappin.and.ellipse", "Адрес", p.address)
                    if let h = p.hours, !h.isEmpty { infoRow("clock", "Часы работы", h) }
                    if let ph = p.phone, !ph.isEmpty { infoRow("phone", "Телефон", ph) }
                    if let st = p.site, !st.isEmpty { infoRow("safari", "Сайт", st) }
                    if p.status == "rejected", let r = p.rejectReason { infoRow("exclamationmark.bubble", "Причина отказа", r) }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    if p.status != "approved" {
                        Button { Task { await decide(p, true) } } label: {
                            Label("Одобрить", systemImage: "checkmark")
                                .font(.headline)
                                .foregroundStyle(Color.onLime)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if p.status != "rejected" {
                        Button { rejecting = p } label: {
                            Label(p.status == "approved" ? "Снять с карты" : "Отклонить", systemImage: "xmark")
                                .font(.headline)
                                .foregroundStyle(Color(hex: 0xFF5A4E))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color(hex: 0xFF5A4E).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .background(Color.oxCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.06)))
    }

    private func infoRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(Color.limeInk).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(Color.oxHint)
                Text(value).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
    }

    private func statusTitle(_ s: String?) -> String { s == "approved" ? "На карте" : s == "rejected" ? "Отклонено" : "На проверке" }
    private func statusColor(_ s: String?) -> Color { s == "approved" ? Color.lime : s == "rejected" ? Color(hex: 0xFF5A4E) : Color.orange }

    private func load() async {
        loading = true
        defer { loading = false }
        if let r: MapShopsResponse = try? await API.call("/m/platform/map-places", query: ["status": status]) {
            withAnimation(.smooth(duration: 0.25)) { items = r.items }
        }
    }

    private func decide(_ p: MapShopPlace, _ ok: Bool, reason: String = "") async {
        do {
            let _: OK = try await API.call("/m/platform/map-places/\(p.id)/\(ok ? "approve" : "reject")", method: "POST",
                                           body: ok ? [:] : ["reason": reason])
            OxHaptics.play(ok ? .setDone : .select)
            OxAlert.show(icon: ok ? "checkmark.seal.fill" : "xmark.seal.fill", title: ok ? "Магазин на карте" : "Заявка отклонена",
                         message: ok ? "\(p.name) теперь видят все пользователи" : "Владелец получит уведомление с причиной")
            withAnimation(.smooth(duration: 0.3)) { items.removeAll { $0.id == p.id } }
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

/// Причина отказа: быстрые варианты или свой текст
struct RejectPlaceSheet: View {
    let place: MapShopPlace
    var onReject: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    private let quick = ["Точка стоит не на входе в магазин", "Адрес не совпадает с точкой", "Это не магазин спортпита", "Неверные часы работы или телефон"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Быстрый ответ") {
                    ForEach(quick, id: \.self) { q in
                        Button {
                            reason = q
                            Haptic.tap(.soft)
                        } label: {
                            HStack {
                                Text(q).foregroundStyle(.primary)
                                Spacer()
                                if reason == q { Image(systemName: "checkmark").foregroundStyle(Color.limeInk) }
                            }
                        }
                    }
                }
                Section("Или своими словами") {
                    TextField("Причина отказа", text: $reason, axis: .vertical).lineLimit(2...4)
                }
            }
            .oxFitSheet()
            .navigationTitle("Отклонить «\(place.name)»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отклонить") {
                        onReject(reason.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .bold()
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
