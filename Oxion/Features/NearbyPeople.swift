import SwiftUI
import MultipeerConnectivity
import NearbyInteraction
import Observation

// «Рядом»: пользователи OXION поблизости через UWB (Nearby Interaction).
// 1) Телефоны находят друг друга по Bluetooth/Wi-Fi (MultipeerConnectivity) и обмениваются токенами UWB.
// 2) NISession измеряет точное расстояние и направление (нужен чип U1/U2 у обоих — iPhone 11 и новее, кроме SE).
// Виден только тот, у кого этот экран открыт прямо сейчас. Ничего не отправляется на сервер.

struct NearbyPeer: Identifiable, Equatable {
    let id: MCPeerID
    var userId: Int?
    var name: String
    var photo: String?
    var distance: Float?
    var direction: SIMD3<Float>?
    var horizontalAngle: Float?
    var lastSeen = Date()
    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.distance == b.distance && a.direction == b.direction && a.userId == b.userId && a.horizontalAngle == b.horizontalAngle
    }
}

private struct Hello: Codable { let uid: Int; let name: String; let photo: String?; let token: Data }

@MainActor
@Observable
final class NearbyManager: NSObject {
    private(set) var peers: [NearbyPeer] = []
    private(set) var running = false
    private(set) var errorText: String?
    static var uwbSupported: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }
    static var directionSupported: Bool {
        let c = NISession.deviceCapabilities
        return c.supportsDirectionMeasurement || c.supportsCameraAssistance
    }

    @ObservationIgnored private var me: (id: Int, name: String, photo: String?) = (0, "OXION", nil)
    @ObservationIgnored private var peerID: MCPeerID!
    @ObservationIgnored private var session: MCSession!
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var ni: [MCPeerID: NISession] = [:]
    @ObservationIgnored private var tokens: [MCPeerID: NIDiscoveryToken] = [:]
    static let service = "oxion-near"

    func start(uid: Int, name: String, photo: String?) {
        guard !running else { return }
        me = (uid, name, photo)
        peerID = MCPeerID(displayName: String(name.prefix(30)).isEmpty ? "OXION" : String(name.prefix(30)))
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let a = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["uid": String(uid)], serviceType: Self.service)
        a.delegate = self
        a.startAdvertisingPeer()
        let b = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.service)
        b.delegate = self
        b.startBrowsingForPeers()
        advertiser = a; browser = b
        running = true
        errorText = Self.uwbSupported ? nil : "На этом iPhone нет UWB — покажем только, кто рядом, без расстояния"
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        for s in ni.values { s.invalidate() }
        ni = [:]; tokens = [:]; peers = []
        running = false
    }

    // создаём отдельную UWB-сессию на каждого собеседника и отправляем ему свой токен
    private func sendHello(to p: MCPeerID) {
        let s = ni[p] ?? {
            let n = NISession()
            n.delegate = self
            ni[p] = n
            return n
        }()
        var tokenData = Data()
        if let t = s.discoveryToken, let d = try? NSKeyedArchiver.archivedData(withRootObject: t, requiringSecureCoding: true) { tokenData = d }
        let hello = Hello(uid: me.id, name: me.name, photo: me.photo, token: tokenData)
        if let d = try? JSONEncoder().encode(hello) { try? session.send(d, toPeers: [p], with: .reliable) }
    }

    private func received(_ h: Hello, from p: MCPeerID) {
        if let i = peers.firstIndex(where: { $0.id == p }) {
            peers[i].userId = h.uid; peers[i].name = h.name; peers[i].photo = h.photo
        } else {
            peers.append(NearbyPeer(id: p, userId: h.uid, name: h.name, photo: h.photo))
            OxHaptics.play(.select)
        }
        guard Self.uwbSupported, !h.token.isEmpty,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: h.token),
              let s = ni[p] else { return }
        tokens[p] = token
        let cfg = NINearbyPeerConfiguration(peerToken: token)
        if NISession.deviceCapabilities.supportsCameraAssistance { cfg.isCameraAssistanceEnabled = true }
        s.run(cfg)
    }

    private func update(_ obj: NINearbyObject, in s: NISession) {
        guard let p = ni.first(where: { $0.value === s })?.key, let i = peers.firstIndex(where: { $0.id == p }) else { return }
        peers[i].distance = obj.distance
        peers[i].direction = obj.direction
        peers[i].horizontalAngle = obj.horizontalAngle
        peers[i].lastSeen = Date()
        peers.sort { ($0.distance ?? 99) < ($1.distance ?? 99) }
    }

    private func lost(_ p: MCPeerID) {
        ni[p]?.invalidate()
        ni[p] = nil
        tokens[p] = nil
        peers.removeAll { $0.id == p }
    }
}

extension NearbyManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, NISessionDelegate {
    nonisolated func session(_ session: MCSession, peer p: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected: self.sendHello(to: p)
            case .notConnected: self.lost(p)
            default: break
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer p: MCPeerID) {
        guard let h = try? JSONDecoder().decode(Hello.self, from: data) else { return }
        Task { @MainActor in self.received(h, from: p) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in invitationHandler(true, self.session) }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let t = error.localizedDescription
        Task { @MainActor in self.errorText = "Не удалось начать поиск: \(t). Проверьте доступ к локальной сети в настройках." }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let theirs = Int(info?["uid"] ?? "") ?? 0
        Task { @MainActor in
            // приглашает тот, у кого id меньше — чтобы не было двух соединений
            guard theirs != self.me.id, self.me.id < theirs || theirs == 0 else { return }
            browser.invitePeer(p, to: self.session, withContext: nil, timeout: 20)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer p: MCPeerID) {
        Task { @MainActor in self.lost(p) }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let t = error.localizedDescription
        Task { @MainActor in self.errorText = "Не удалось начать поиск: \(t)" }
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let o = nearbyObjects.first else { return }
        Task { @MainActor in self.update(o, in: session) }
    }
    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            guard let p = self.ni.first(where: { $0.value === session })?.key else { return }
            if reason == .timeout, let t = self.tokens[p] { session.run(NINearbyPeerConfiguration(peerToken: t)) }
        }
    }
    nonisolated func sessionWasSuspended(_ session: NISession) {}
    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            guard let p = self.ni.first(where: { $0.value === session })?.key, let t = self.tokens[p] else { return }
            session.run(NINearbyPeerConfiguration(peerToken: t))
        }
    }
    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        let t = error.localizedDescription
        Task { @MainActor in
            if let p = self.ni.first(where: { $0.value === session })?.key { self.ni[p] = nil }
            if (error as NSError).code == NIError.userDidNotAllow.rawValue {
                self.errorText = "Нет разрешения на «Взаимодействие рядом». Включите в Настройки → Oxion."
            } else { self.errorText = t }
        }
    }
}

struct NearbyPeopleView: View {
    @Environment(AppModel.self) private var model
    @State private var m = NearbyManager()
    @State private var focusId: MCPeerID?
    @State private var lastBucket: Int?

    private var focus: NearbyPeer? {
        if let focusId, let p = m.peers.first(where: { $0.id == focusId }) { return p }
        return nil
    }
    private var sorted: [NearbyPeer] { m.peers.sorted { ($0.distance ?? 99) < ($1.distance ?? 99) } }

    var body: some View {
        ZStack {
            if let p = focus {
                LocatorView(peer: p) { withAnimation(.spring(duration: 0.4)) { focusId = nil } }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                List {
                    // как AirDrop: я в центре, вокруг мягкие волны, найденные люди — пузырями по кругу
                    Section {
                        NearbyOrbit(peers: m.peers, me: model.me) { p in open(p) }
                            .frame(height: 300)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        if sorted.isEmpty {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Поиск…").foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            ForEach(sorted) { p in
                                Button { open(p) } label: { row(p) }
                                    .swipeActions {
                                        if let uid = p.userId {
                                            NavigationLink { UserProfileView(userId: uid) } label: { Label("Профиль", systemImage: "person.crop.circle") }
                                                .tint(.blue)
                                        }
                                    }
                            }
                        }
                    } header: {
                        Text("Поблизости")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let e = m.errorText { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            Text("Вас видят только те, у кого тоже открыт экран «Рядом». Точное расстояние и направление — на iPhone 11 и новее (кроме SE), когда UWB есть у обоих. Данные не отправляются на сервер.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .transition(.opacity)
            }
        }
        .navigationTitle(focus == nil ? "Рядом" : (focus?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(duration: 0.45), value: m.peers.map(\.id))
        .onAppear {
            m.start(uid: model.me?.id ?? 0, name: model.me?.name ?? model.me?.tgName ?? "OXION", photo: model.me?.photoUrl)
        }
        .onDisappear { m.stop() }
        // вибрация «теплее/холоднее»: каждые полметра — щелчок, совсем рядом — успех
        .onChange(of: focus?.distance) { _, d in
            guard let d else { return }
            let b = Int(d / 0.5)
            if let lb = lastBucket, b != lb {
                if d < 0.5 { Haptic.success() } else { Haptic.tap(b < lb ? .medium : .light) }
            }
            lastBucket = b
        }
        .onChange(of: focusId) { lastBucket = nil }
    }

    private func open(_ p: NearbyPeer) {
        Haptic.tap(.medium)
        withAnimation(.spring(duration: 0.45)) { focusId = p.id }
    }

    private func row(_ p: NearbyPeer) -> some View {
        HStack(spacing: 12) {
            Avatar(url: API.media(p.photo), name: p.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(p.distance.map { NearbyFmt.dist($0) + NearbyFmt.side(p) } ?? String(localized: "рядом · уточняем расстояние"))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if let a = NearbyFmt.angle(p) {
                Image(systemName: "location.north.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .rotationEffect(.radians(a))
                    .animation(.spring(response: 0.3), value: a)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

enum NearbyFmt {
    static func dist(_ d: Float) -> String {
        d < 1 ? String(format: "%.0f см", d * 100) : String(format: "%.1f м", d).replacingOccurrences(of: ".", with: ",")
    }
    static func angle(_ p: NearbyPeer) -> Double? {
        if let h = p.horizontalAngle { return Double(h) }
        if let d = p.direction { return Double(atan2(d.x, -d.z)) }
        return nil
    }
    /// « · слева», « · впереди» — как в «Локаторе»
    static func side(_ p: NearbyPeer) -> String {
        guard let a = angle(p) else { return "" }
        let deg = a * 180 / .pi
        if abs(deg) < 20 { return " · " + String(localized: "впереди") }
        if abs(deg) > 150 { return " · " + String(localized: "позади") }
        return " · " + (deg > 0 ? String(localized: "справа") : String(localized: "слева"))
    }
}

// MARK: - Орбита в стиле AirDrop

struct NearbyOrbit: View {
    let peers: [NearbyPeer]
    let me: Me?
    var onPick: (NearbyPeer) -> Void

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let orbit = min(g.size.width, g.size.height) / 2 - 46
            ZStack {
                // мягкие волны от центра, как «Поиск» в AirDrop
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !PowerSaver.allowsNow(.interface))) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<4, id: \.self) { k in
                            let ph = ((t / 3.2) + Double(k) / 4).truncatingRemainder(dividingBy: 1)
                            Circle()
                                .stroke(Color.blue.opacity(0.28 * (1 - ph)), lineWidth: 1)
                                .frame(width: 70 + (orbit * 2 + 40) * ph, height: 70 + (orbit * 2 + 40) * ph)
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
                .allowsHitTesting(false)

                // тонкая орбита, на которой появляются люди
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    .frame(width: orbit * 2, height: orbit * 2)
                    .position(c)

                // я
                VStack(spacing: 6) {
                    Avatar(url: API.media(me?.photoUrl), name: me?.name ?? "Я", size: 64)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 3))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    Text("Вы").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .position(x: c.x, y: c.y + 12)

                // люди рядом: по направлению, если оно есть, иначе ровно по кругу
                ForEach(Array(peers.enumerated()), id: \.element.id) { i, p in
                    let a = NearbyFmt.angle(p) ?? (Double(i) / Double(max(1, peers.count))) * 2 * .pi - .pi / 4
                    let rr = orbit * CGFloat(0.55 + 0.45 * min(1, Double(p.distance ?? 6) / 6))
                    Button { onPick(p) } label: {
                        VStack(spacing: 4) {
                            Avatar(url: API.media(p.photo), name: p.name, size: 54)
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2.5))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                            Text(p.name).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                .frame(maxWidth: 90)
                            if let d = p.distance {
                                Text(NearbyFmt.dist(d)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: c.x + sin(a) * rr, y: c.y - cos(a) * rr)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: p.distance)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: a)
                }
            }
        }
    }
}

// MARK: - Поиск одного человека (как «Локатор» Apple)

struct LocatorView: View {
    let peer: NearbyPeer
    var onClose: () -> Void

    private var close: Bool { (peer.distance ?? 99) < 0.6 }

    var body: some View {
        ZStack {
            // как в «Локаторе»: совсем рядом — весь экран зелёный
            (close ? Color.green : Color(.systemBackground))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: close)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Avatar(url: API.media(peer.photo), name: peer.name, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(peer.name).font(.headline)
                        Text(hint).font(.subheadline).foregroundStyle(close ? .white.opacity(0.85) : .secondary)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                ZStack {
                    if close {
                        Avatar(url: API.media(peer.photo), name: peer.name, size: 170)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                            .background(Circle().fill(.white.opacity(0.25)).scaleEffect(1.25))
                            .transition(.scale.combined(with: .opacity))
                    } else if let a = NearbyFmt.angle(peer) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 190, weight: .bold))
                            .foregroundStyle(.primary)
                            .rotationEffect(.radians(a))
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: a)
                    } else {
                        // направления пока нет — точки, как в «Локаторе» до первого направления
                        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                            let t = tl.date.timeIntervalSinceReferenceDate
                            ZStack {
                                ForEach(0..<12, id: \.self) { i in
                                    Circle().fill(Color.secondary.opacity(0.25 + 0.5 * (0.5 + 0.5 * sin(t * 3 + Double(i)))))
                                        .frame(width: 10, height: 10)
                                        .offset(y: -90)
                                        .rotationEffect(.degrees(Double(i) * 30))
                                }
                            }
                        }
                    }
                }
                .frame(height: 280)
                .animation(.spring(duration: 0.4), value: close)

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.distance.map { NearbyFmt.dist($0) } ?? "—")
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: peer.distance)
                    Text(close ? String(localized: "Рядом") : sideText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(close ? .white : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)

                if let uid = peer.userId {
                    NavigationLink { UserProfileView(userId: uid) } label: {
                        Text("Открыть профиль").font(.headline)
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .buttonStyle(.glass)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .foregroundStyle(close ? .white : .primary)
        }
    }

    private var hint: String {
        if close { return String(localized: "Вы почти на месте") }
        if NearbyFmt.angle(peer) == nil { return String(localized: "Медленно поворачивайтесь — уточняем направление") }
        return String(localized: "Идите по стрелке")
    }

    private var sideText: String {
        guard let a = NearbyFmt.angle(peer) else { return String(localized: "расстояние") }
        let deg = a * 180 / .pi
        if abs(deg) < 20 { return String(localized: "впереди") }
        if abs(deg) > 150 { return String(localized: "позади") }
        return deg > 0 ? String(localized: "справа") : String(localized: "слева")
    }
}
