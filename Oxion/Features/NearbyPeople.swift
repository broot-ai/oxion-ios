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

    var body: some View {
        ZStack {
            // тёмный фон с мягким лаймовым свечением в центре
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color.lime.opacity(glowLevel), .clear], center: .center, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: glowLevel)

            if let p = focus {
                LocatorView(peer: p) { withAnimation(.spring(duration: 0.4)) { focusId = nil } }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView {
                    VStack(spacing: 22) {
                        NearbyRadar(peers: m.peers, me: model.me) { p in
                            Haptic.tap(.medium)
                            withAnimation(.spring(duration: 0.45)) { focusId = p.id }
                        }
                        .frame(height: 340)
                        .padding(.top, 6)

                        if let e = m.errorText {
                            Label(e, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        if m.peers.isEmpty {
                            VStack(spacing: 8) {
                                Text("Ищем пользователей OXION рядом…").font(.headline)
                                Text("Попросите друга тоже открыть «Рядом». Точное расстояние и направление работают на iPhone 11 и новее (кроме SE) — с чипом UWB у обоих.")
                                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 28)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(m.peers.sorted { ($0.distance ?? 99) < ($1.distance ?? 99) }) { p in card(p) }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 30)
                }
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle(focus == nil ? "Рядом" : (focus?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
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

    /// чем ближе выбранный человек, тем ярче фон
    private var glowLevel: Double {
        guard let d = focus?.distance else { return 0.10 }
        return 0.10 + 0.35 * Double(max(0, 1 - min(d, 8) / 8))
    }

    private func card(_ p: NearbyPeer) -> some View {
        HStack(spacing: 12) {
            Avatar(url: API.media(p.photo), name: p.name, size: 48)
                .overlay(Circle().stroke(Color.lime, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.headline)
                Text(p.distance.map { NearbyFmt.dist($0) } ?? "рядом · расстояние уточняется")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if let a = NearbyFmt.angle(p) {
                Image(systemName: "location.north.fill")
                    .font(.title3).foregroundStyle(Color.lime)
                    .rotationEffect(.radians(a))
                    .animation(.spring(response: 0.3), value: a)
            }
            Button {
                Haptic.tap(.medium)
                withAnimation(.spring(duration: 0.45)) { focusId = p.id }
            } label: {
                Text("Найти").font(.subheadline.bold()).padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
            if let uid = p.userId {
                NavigationLink { UserProfileView(userId: uid) } label: {
                    Image(systemName: "person.crop.circle").font(.title3)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
    /// 0…1 по радиусу радара: ближние метры растянуты
    static func radius(_ d: Float?) -> CGFloat {
        guard let d else { return 0.82 }
        return CGFloat(min(1, sqrt(max(0, d) / 9)))
    }
}

// MARK: - Радар

struct NearbyRadar: View {
    let peers: [NearbyPeer]
    let me: Me?
    var onPick: (NearbyPeer) -> Void

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2 - 12
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                // круги расстояний с подписями
                ForEach([1, 3, 6, 9], id: \.self) { m in
                    let rr = r * NearbyFmt.radius(Float(m))
                    Circle().stroke(Color.lime.opacity(m == 9 ? 0.35 : 0.16), lineWidth: m == 9 ? 1.5 : 1)
                        .frame(width: rr * 2, height: rr * 2)
                    Text("\(m) м").font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.lime.opacity(0.55))
                        .offset(x: rr * 0.72, y: -rr * 0.72)
                }
                // деления по краю, как у компаса
                ForEach(0..<36, id: \.self) { i in
                    Capsule().fill(Color.lime.opacity(i % 9 == 0 ? 0.7 : 0.22))
                        .frame(width: i % 9 == 0 ? 2 : 1, height: i % 9 == 0 ? 10 : 5)
                        .offset(y: -r - 2)
                        .rotationEffect(.degrees(Double(i) * 10))
                }
                // бегущий луч
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !PowerSaver.allowsNow(.interface))) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let ang = (t.truncatingRemainder(dividingBy: 3) / 3) * 360
                    ZStack {
                        AngularGradient(colors: [Color.lime.opacity(0.0), Color.lime.opacity(0.0), Color.lime.opacity(0.35)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(90))
                            .mask(Circle().frame(width: r * 2, height: r * 2))
                            .rotationEffect(.degrees(ang - 90))
                        Rectangle().fill(LinearGradient(colors: [Color.lime.opacity(0.9), .clear], startPoint: .bottom, endPoint: .top))
                            .frame(width: 1.5, height: r)
                            .offset(y: -r / 2)
                            .rotationEffect(.degrees(ang))
                        // расходящиеся волны
                        ForEach(0..<3, id: \.self) { k in
                            let ph = ((t / 2.4) + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                            Circle().stroke(Color.lime.opacity(0.5 * (1 - ph)), lineWidth: 1.5)
                                .frame(width: r * 2 * ph, height: r * 2 * ph)
                        }
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
                .allowsHitTesting(false)

                // я
                Avatar(url: API.media(me?.photoUrl), name: me?.name ?? "Я", size: 50)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                    .shadow(color: Color.lime.opacity(0.6), radius: 12)
                    .position(c)

                // люди рядом
                ForEach(peers) { p in
                    let a = NearbyFmt.angle(p) ?? Double(abs(p.id.hashValue % 628)) / 100
                    let d = r * NearbyFmt.radius(p.distance)
                    Button { onPick(p) } label: {
                        VStack(spacing: 3) {
                            Avatar(url: API.media(p.photo), name: p.name, size: 42)
                                .overlay(Circle().stroke(Color.lime, lineWidth: 2.5))
                                .background(PulseDot())
                            Text(p.distance.map { NearbyFmt.dist($0) } ?? p.name)
                                .font(.caption2.bold().monospacedDigit())
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .glassEffect(.regular, in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: c.x + sin(a) * d, y: c.y - cos(a) * d)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: p.distance)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: a)
                }
            }
        }
    }
}

/// пульсирующее свечение вокруг найденного человека
struct PulseDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Color.lime.opacity(0.35))
            .scaleEffect(on ? 1.9 : 1)
            .opacity(on ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true } }
    }
}

// MARK: - Локатор одного человека (как «Локатор» Apple)

struct LocatorView: View {
    let peer: NearbyPeer
    var onClose: () -> Void

    private var close: Bool { (peer.distance ?? 99) < 0.6 }

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 10) {
                Avatar(url: API.media(peer.photo), name: peer.name, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(peer.name).font(.headline)
                    Text(hint).font(.subheadline).foregroundStyle(.secondary).contentTransition(.opacity)
                }
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            .padding(.horizontal, 20)

            Spacer()

            ZStack {
                if close {
                    // совсем рядом — вместо стрелки пульсирующий круг
                    Circle().fill(Color.lime).frame(width: 190, height: 190)
                        .overlay(Avatar(url: API.media(peer.photo), name: peer.name, size: 150))
                        .background(PulseDot().frame(width: 190, height: 190))
                        .transition(.scale.combined(with: .opacity))
                } else if let a = NearbyFmt.angle(peer) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 170, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.white, Color.lime], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color.lime.opacity(0.6), radius: 30)
                        .rotationEffect(.radians(a))
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: a)
                } else {
                    // направления пока нет: только расстояние
                    ZStack {
                        Circle().stroke(Color.lime.opacity(0.25), lineWidth: 2).frame(width: 200, height: 200)
                        PulseDot().frame(width: 120, height: 120)
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 54, weight: .semibold)).foregroundStyle(Color.lime)
                    }
                }
            }
            .frame(height: 260)
            .animation(.spring(duration: 0.4), value: close)

            VStack(spacing: 4) {
                Text(peer.distance.map { NearbyFmt.dist($0) } ?? "—")
                    .font(.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: peer.distance)
                Text(close ? "Вы рядом!" : sideText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(close ? Color.lime : .secondary)
            }

            Spacer()

            if let uid = peer.userId {
                NavigationLink { UserProfileView(userId: uid) } label: {
                    Label("Открыть профиль", systemImage: "person.crop.circle").font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.glass)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private var hint: String {
        if NearbyFmt.angle(peer) == nil { return "Медленно повернитесь — уточняем направление" }
        return "Идите по стрелке"
    }

    private var sideText: String {
        guard let a = NearbyFmt.angle(peer) else { return "расстояние" }
        let deg = a * 180 / .pi
        if abs(deg) < 20 { return "прямо перед вами" }
        if abs(deg) > 150 { return "позади вас" }
        return deg > 0 ? "справа" : "слева"
    }
}
