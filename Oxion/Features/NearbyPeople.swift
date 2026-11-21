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
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            radar
                .frame(height: 300)
                .padding(.top, 8)
            if let e = m.errorText {
                Label(e, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }
            if m.peers.isEmpty {
                VStack(spacing: 6) {
                    Text("Ищем пользователей OXION рядом…").font(.headline)
                    Text("Попросите друга тоже открыть «Рядом». Точное расстояние и направление работают на iPhone 11 и новее (кроме SE) — с чипом UWB у обоих.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            } else {
                List(m.peers) { p in
                    NavigationLink {
                        if let uid = p.userId { UserProfileView(userId: uid) } else { Text(p.name) }
                    } label: { row(p) }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            Spacer(minLength: 0)
        }
        .navigationTitle("Рядом")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            m.start(uid: model.me?.id ?? 0, name: model.me?.name ?? model.me?.tgName ?? "OXION", photo: model.me?.photoUrl)
            pulse = true
        }
        .onDisappear { m.stop() }
    }

    private var radar: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2 - 10
            ZStack {
                ForEach(0..<3) { i in
                    Circle().stroke(Color.lime.opacity(0.18), lineWidth: 1)
                        .frame(width: r * 2 * CGFloat(i + 1) / 3, height: r * 2 * CGFloat(i + 1) / 3)
                }
                Circle().fill(Color.lime.opacity(0.12))
                    .frame(width: r * 2, height: r * 2)
                    .scaleEffect(pulse ? 1 : 0.2)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: pulse)
                Avatar(url: API.media(model.me?.photoUrl), name: model.me?.name ?? "Я", size: 44)
                ForEach(m.peers) { p in
                    let d = CGFloat(min(p.distance ?? 6, 6)) / 6 * r
                    let a = CGFloat(p.horizontalAngle ?? atan2(p.direction?.x ?? 0, -(p.direction?.z ?? -1)))
                    VStack(spacing: 2) {
                        Avatar(url: API.media(p.photo), name: p.name, size: 40)
                            .overlay(Circle().stroke(Color.lime, lineWidth: 2))
                        if let dist = p.distance {
                            Text(String(format: "%.1f м", dist)).font(.caption2.bold().monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 2).background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .offset(x: sin(a) * d, y: -cos(a) * d)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: p.distance)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    private func row(_ p: NearbyPeer) -> some View {
        HStack(spacing: 12) {
            Avatar(url: API.media(p.photo), name: p.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.headline)
                Text(p.distance.map { String(format: "%.1f м", $0) } ?? "рядом · расстояние уточняется")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if p.direction != nil || p.horizontalAngle != nil {
                let a = Double(p.horizontalAngle ?? atan2(p.direction?.x ?? 0, -(p.direction?.z ?? -1)))
                Image(systemName: "location.north.fill")
                    .font(.title2).foregroundStyle(Color.limeInk)
                    .rotationEffect(.radians(a))
                    .animation(.spring(response: 0.3), value: a)
            }
        }
    }
}
