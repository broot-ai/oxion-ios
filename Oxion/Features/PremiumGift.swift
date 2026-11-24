import SwiftUI

// Oxion Premium: подписка и подарки собеседникам — как «Подарить Premium» в Telegram.
// Оплата пока в тестовом режиме: подарок активируется сразу.

// MARK: - Модели

struct PremiumPlan: Decodable, Identifiable, Hashable {
    let key: String
    let months: Int
    let title: String
    let price: Int
    let discount: Int?
    let color: String?
    var id: String { key }

    var tint: Color {
        switch color {
        case "blue": Color(hex: 0x3B8CF5)
        case "red", "purple": Color(hex: 0x9B5CFF)
        default: Color(hex: 0x4CD964)
        }
    }
    /// картинка коробки: зелёная / синяя / фиолетовая
    var asset: String {
        switch color {
        case "blue": "gift-blue"
        case "red", "purple": "gift-purple"
        default: "gift-green"
        }
    }
    var priceText: String { "\(price.formatted(.number.locale(L10n.locale))) ₽" }
    var titleFull: String { "Premium на \(months == 12 ? "1 год" : months == 1 ? "1 месяц" : "\(months) месяца")" }
}

struct PremiumPerk: Decodable, Hashable { let icon: String; let title: String; let text: String }

struct PremiumInfo: Decodable {
    struct To: Decodable { let id: Int; let name: String?; let photo: String?; let premiumUntil: Double? }
    let until: Double?
    let active: Bool
    let plans: [PremiumPlan]
    let perks: [PremiumPerk]
    let to: To?
}

struct GiftResult: Decodable { let ok: Bool?; let chatId: Int?; let messageId: Int?; let until: Double? }

private func untilText(_ ms: Double) -> String {
    let f = DateFormatter()
    f.locale = L10n.locale
    f.dateFormat = "d MMMM yyyy"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
}

// MARK: - Коробка подарка

/// Коробка подарка (картинка по тарифу) — слегка «дышит»
struct GiftBoxIcon: View {
    var asset: String
    var size: CGFloat = 64

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: size * 0.08, y: size * 0.06)
    }
}

/// Золотой кубок Oxion — статичная картинка с мягким «дыханием»
struct AnimatedTrophy: View {
    var height: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var up = false

    var body: some View {
        Image("premium-trophy")
            .resizable()
            .scaledToFit()
            .frame(width: height * 1.1, height: height * 1.1)
            .scaleEffect(up && !reduce ? 1.04 : 1)
            .shadow(color: Color(hex: 0xFFB000).opacity(0.3), radius: 22, y: 8)
            .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever()) { up = true } }
    }
}

/// Диагональная лаймовая лента в углу карточки
struct LimeRibbon: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Color.onLime)
            .frame(width: 96, height: 20)
            .background(
                LinearGradient(colors: [Color.lime, Color.lime.mix(with: .green, by: 0.25)], startPoint: .leading, endPoint: .trailing)
            )
            .shadow(color: Color.lime.opacity(0.5), radius: 4)
            .rotationEffect(.degrees(45))
            .offset(x: 28, y: 16)
    }
}

/// Искры как в Telegram Premium: четырёхлучевые звёздочки SF Symbols разных размеров разлетаются от центра
struct Sparkles: View {
    var colors: [Color] = [Color(hex: 0xFFC53D), Color(hex: 0xFFB000), Color(hex: 0xFFE680), Color.lime]
    var count = 34

    private struct P { let angle: Double; let speed: Double; let size: Double; let phase: Double; let color: Int; let symbol: Int }
    private let ps: [P]

    init(colors: [Color]? = nil, count: Int = 34) {
        if let colors { self.colors = colors }
        self.count = count
        var list: [P] = []
        for i in 0..<count {
            func r(_ k: Int) -> Double {
                let x = sin(Double(i * 7919 + k * 104729) * 0.0173) * 43758.5453
                return x - floor(x)
            }
            list.append(P(angle: r(1) * .pi * 2, speed: 0.35 + r(2) * 0.65, size: 5 + pow(r(3), 1.6) * 15,
                          phase: r(4), color: Int(r(5) * 100), symbol: r(6) < 0.7 ? 0 : 1))
        }
        ps = list
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = hypot(size.width, size.height) / 2
                let sym = [ctx.resolve(Image(systemName: "sparkle")), ctx.resolve(Image(systemName: "plus"))]
                for p in ps {
                    // жизнь частицы 0…1: вылетает из центра, растёт и гаснет у края
                    let life = (t * 0.16 * p.speed + p.phase).truncatingRemainder(dividingBy: 1)
                    let d = 24 + life * maxR
                    let x = c.x + cos(p.angle) * d
                    let y = c.y + sin(p.angle) * d * 0.8
                    let fade = min(1, life * 4) * (1 - life)
                    let sz = p.size * (0.5 + life * 0.7)
                    var g = ctx
                    g.opacity = fade
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .degrees(life * 90))
                    var img = sym[p.symbol]
                    img.shading = .color(colors[p.color % colors.count])
                    g.draw(img, in: CGRect(x: -sz / 2, y: -sz / 2, width: sz, height: sz))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Шторка ровно по высоте содержимого
struct FitSheet: ViewModifier {
    @State private var h: CGFloat = 400
    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(h)])
    }
}

extension View {
    func fitSheet() -> some View { modifier(FitSheet()) }
}

// MARK: - Панель «Подарить Premium» (вкладка «Подарок» в чате)

struct GiftPremiumPanel: View {
    let userId: Int
    var name: String
    var photo: String?
    var onSent: (Int?) -> Void = { _ in }
    /// высота содержимого — чтобы шторка открывалась ровно по нему
    var onHeight: (CGFloat) -> Void = { _ in }

    @State private var info: PremiumInfo?
    @State private var error: String?
    @State private var pick: PremiumPlan?
    @State private var showPerks = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Sparkles().frame(height: 118).padding(.horizontal, 20)
                    Avatar(url: API.media(photo ?? info?.to?.photo), name: name, size: 92)
                        .shadow(color: Color(hex: 0xFFC53D).opacity(0.35), radius: 20)
                }

                Text("Подарить Premium").font(.system(size: 26, weight: .heavy))
                (Text("Подарите **\(name)** доступ к эксклюзивным функциям Oxion. ")
                 + Text("Подробнее о Premium ›").foregroundColor(Color.lime))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, -4)
                    .onTapGesture { showPerks = true }

                if let until = info?.to?.premiumUntil {
                    Label("У \(name) уже есть Premium до \(untilText(until)) — подарок продлит его", systemImage: "star.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: 0xFFC53D))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(hex: 0xFFC53D).opacity(0.12), in: Capsule())
                }

                if let plans = info?.plans {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(plans) { p in
                                PlanCard(plan: p) { pick = p }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(.secondary).padding()
                } else {
                    ProgressView().padding(30)
                }

                VStack(spacing: 6) {
                    Text("Что даёт Premium").font(.title3.bold())
                    Text("Безлимитный ИИ-тренер, сканер еды до 400 раз в день, значок и особое оформление.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Подробнее о Premium ›") { showPerks = true }
                        .font(.subheadline.bold()).foregroundStyle(Color.lime)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }
            .padding(.bottom, 92)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            do { info = try await API.call("/premium", query: ["to": String(userId)]) }
            catch { self.error = error.localizedDescription }
        }
        .sheet(item: $pick) { p in
            GiftConfirmSheet(plan: p, userId: userId, name: name) { r in
                pick = nil
                onSent(r.messageId)
            }
        }
        .sheet(isPresented: $showPerks) { PremiumView(embedded: true) }
    }
}

private struct PlanCard: View {
    let plan: PremiumPlan
    var tap: () -> Void

    var body: some View {
        Button(action: { Haptic.tap(); tap() }) {
            VStack(spacing: 2) {
                GiftBoxIcon(asset: plan.asset, size: 76)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                Text(plan.title).font(.subheadline.weight(.heavy)).foregroundStyle(.primary)
                Text("Premium").font(.caption.weight(.medium)).foregroundStyle(.primary.opacity(0.8))
                Text(plan.priceText)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Color.lime)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.lime.opacity(0.16), in: Capsule())
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if let d = plan.discount, d > 0 { LimeRibbon(text: "−\(d)%") }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(GiftPress())
    }
}

private struct GiftPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

// MARK: - Подтверждение подарка

struct GiftConfirmSheet: View {
    let plan: PremiumPlan
    let userId: Int
    let name: String
    var onSent: (GiftResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var sending = false
    @State private var sent = false
    @FocusState private var focus: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 12)

            Group {
                VStack(spacing: 12) {
                    Text("Вы отправляете подарок за \(plan.priceText)")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())

                    VStack(spacing: 6) {
                        GiftBoxIcon(asset: plan.asset, size: 120)
                            .padding(.top, 12)
                            .scaleEffect(sent ? 1.25 : 1)
                            .rotationEffect(.degrees(sent ? -8 : 0))
                        Text(plan.titleFull).font(.headline)
                        Text("Подписка на эксклюзивные функции Oxion").font(.caption).foregroundStyle(.secondary)
                        if !note.isEmpty {
                            Text("«\(note)»").font(.subheadline.italic()).multilineTextAlignment(.center).padding(.top, 2)
                        }
                        Text("Подробнее")
                            .font(.caption.bold())
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(.white.opacity(0.12), in: Capsule())
                            .padding(.bottom, 16)
                    }
                    .frame(width: 230)
                    .padding(.horizontal, 10)
                    .background(
                        RadialGradient(colors: [plan.tint.opacity(0.35), .clear], center: .top, startRadius: 4, endRadius: 200),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .overlay(alignment: .topTrailing) {
                        if let d = plan.discount, d > 0 { LimeRibbon(text: "−\(d)%") }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                    TextField("Ваше сообщение (необязательно)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focus)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .onChange(of: note) { if note.count > 200 { note = String(note.prefix(200)) } }

                    Label("Тестовый режим: подарок активируется сразу, деньги не списываются", systemImage: "testtube.2")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 14)

            Button {
                Task { await send() }
            } label: {
                HStack {
                    if sending { ProgressView().tint(Color.onLime) }
                    Text("Отправить подарок за \(plan.priceText)").font(.headline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime)
            .foregroundStyle(Color.onLime)
            .controlSize(.large)
            .disabled(sending || sent)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color.oxBg)
        .fitSheet()
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let r: GiftResult = try await API.call("/premium/gift", method: "POST",
                                                   body: ["user_id": userId, "plan": plan.key, "text": note.trimmingCharacters(in: .whitespacesAndNewlines)])
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { sent = true }
            OxHaptics.play(.workoutDone)
            try? await Task.sleep(for: .milliseconds(650))
            OxAlert.show(icon: "gift.fill", tint: Color.lime, title: "Подарок отправлен", message: "\(name) получил(а) \(plan.titleFull)")
            onSent(r)
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

// MARK: - Подарок в переписке

struct GiftBubble: View {
    let card: JSONValue?
    let mine: Bool
    @State private var showPerks = false

    private var plan: PremiumPlan {
        PremiumPlan(key: card?["plan"]?.string ?? "m1", months: Int(card?["months"]?.string ?? "1") ?? 1,
                    title: card?["title"]?.string ?? "", price: Int(card?["price"]?.string ?? "0") ?? 0, discount: nil, color: card?["color"]?.string)
    }

    var body: some View {
        VStack(spacing: 8) {
            GiftBoxIcon(asset: plan.asset, size: 104).padding(.top, 14)
            Text(plan.titleFull).font(.headline)
            Text(mine ? "Вы подарили \(card?["to"]?.string ?? "собеседнику") подписку Oxion Premium"
                      : "\(card?["from"]?.string ?? "Собеседник") дарит вам подписку Oxion Premium")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let n = card?["note"]?.string, !n.isEmpty {
                Text("«\(n)»").font(.subheadline.italic()).multilineTextAlignment(.center)
            }
            Button(mine ? "Подробнее" : "Посмотреть возможности") { showPerks = true }
                .font(.caption.bold())
                .foregroundStyle(Color.lime)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Color.lime.opacity(0.16), in: Capsule())
                .buttonStyle(.plain)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RadialGradient(colors: [plan.tint.opacity(0.4), .clear], center: .top, startRadius: 4, endRadius: 220)
                Sparkles().opacity(0.7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(isPresented: $showPerks) { PremiumView(embedded: true) }
    }
}

// MARK: - Экран Oxion Premium

struct PremiumView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var info: PremiumInfo?
    @State private var error: String?
    @State private var plan: PremiumPlan?
    @State private var buying = false

    var body: some View {
        if embedded {
            // шторка ровно по содержимому: без прокрутки и пустого места снизу
            main
                .padding(.top, 8)
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .padding(16)
                }
                .background(Color.oxBg)
                .fitSheet()
                .presentationCornerRadius(34)
                .presentationDragIndicator(.visible)
                .task { await load() }
        } else {
            full
        }
    }

    private var full: some View {
        ScrollView { main }
        .background(Color.oxBg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let p = plan {
                Button { Task { await buy(p) } } label: {
                    HStack {
                        if buying { ProgressView().tint(Color.onLime) }
                        Text((info?.active == true ? "Продлить за " : "Подключить за ") + p.priceText).font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.lime).foregroundStyle(Color.onLime)
                .controlSize(.large)
                .disabled(buying)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .task { await load() }
    }

    private var main: some View {
            VStack(spacing: 14) {
                ZStack {
                    Sparkles().frame(height: 190)
                    AnimatedTrophy(height: 150)
                }
                Text("Oxion Premium").font(.system(size: 30, weight: .heavy))
                if let u = info?.until {
                    Label("Активен до \(untilText(u))", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold()).foregroundStyle(Color.lime)
                } else {
                    Text("Больше возможностей для тренировок и питания").font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array((info?.perks ?? []).enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: p.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(perkColor(i), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.subheadline.bold())
                                Text(p.text).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if i < (info?.perks.count ?? 0) - 1 { Divider().padding(.leading, 48) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .oxCardBG(22)

                if !embedded, let plans = info?.plans {
                    VStack(spacing: 10) {
                        ForEach(plans) { p in
                            Button { plan = p } label: {
                                HStack {
                                    Image(systemName: plan == p ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(plan == p ? Color.lime : Color.oxHint)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.title).font(.headline)
                                        if let d = p.discount, d > 0 { Text("Выгода \(d)%").font(.caption.bold()).foregroundStyle(Color(hex: 0x9B5CFF)) }
                                    }
                                    Spacer()
                                    Text(p.priceText).font(.headline.monospacedDigit())
                                }
                                .padding(14)
                                .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(plan == p ? Color.lime : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Подарить Premium другу можно в чате: скрепка → «Подарок»")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .padding(.bottom, embedded ? 12 : 100)
    }

    private func perkColor(_ i: Int) -> Color {
        [Color(hex: 0x9B5CFF), Color(hex: 0x3FD6C9), Color(hex: 0x3B8CF5), Color(hex: 0xFFB000), Color(hex: 0xFF5A8A), Color(hex: 0x4CD964)][i % 6]
    }

    private func load() async {
        do {
            info = try await API.call("/premium")
            if plan == nil { plan = info?.plans.dropFirst().first ?? info?.plans.first }
        } catch { self.error = error.localizedDescription }
    }

    private func buy(_ p: PremiumPlan) async {
        buying = true
        defer { buying = false }
        do {
            let _: GiftResult = try await API.call("/premium/buy", method: "POST", body: ["plan": p.key])
            PremiumStatus.shared.active = true
            OxHaptics.play(.workoutDone)
            OxAlert.show(icon: "star.circle.fill", tint: Color(hex: 0xFFB000), title: "Premium подключён", message: "Тестовый режим — без списания денег")
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}


// MARK: - Подарок в переписке по центру, как системное уведомление Telegram

struct GiftServiceRow: View {
    let m: Message
    var peerName: String?
    @State private var details = false

    private var card: JSONValue? { m.card }
    private var plan: PremiumPlan {
        PremiumPlan(key: card?["plan"]?.string ?? "m1", months: Int(card?["months"]?.string ?? "1") ?? 1,
                    title: card?["title"]?.string ?? "", price: Int(card?["price"]?.string ?? "0") ?? 0, discount: nil, color: card?["color"]?.string)
    }
    private var price: String { "\(plan.price.formatted(.number.locale(L10n.locale))) ₽" }

    var body: some View {
        VStack(spacing: 8) {
            Text(m.mine ? "Вы отправили подарок стоимостью \(price)"
                        : "\(card?["from"]?.string ?? peerName ?? "Собеседник") отправил(а) вам подарок стоимостью \(price)")
                .font(.caption.bold())
                .foregroundStyle(.primary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.primary.opacity(0.08), in: Capsule())

            Button { details = true } label: {
                VStack(spacing: 6) {
                    GiftBoxIcon(asset: plan.asset, size: 110).padding(.top, 14)
                    Text(plan.titleFull).font(.headline)
                    Text("Подписка на эксклюзивные функции Oxion").font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let n = card?["note"]?.string, !n.isEmpty {
                        Text("«\(n)»").font(.subheadline.italic()).multilineTextAlignment(.center).padding(.top, 2)
                    }
                    Text("Подробнее")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.1), in: Capsule())
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
                .frame(width: 236)
                .background(RadialGradient(colors: [plan.tint.opacity(0.3), .clear], center: .top, startRadius: 4, endRadius: 200))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(GiftPress())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .sheet(isPresented: $details) { GiftDetailsSheet(m: m, plan: plan) }
    }
}

/// «Подарок вам»: кто подарил, когда, до какого числа действует
struct GiftDetailsSheet: View {
    let m: Message
    let plan: PremiumPlan
    @Environment(\.dismiss) private var dismiss
    @State private var perks = false
    @State private var openUser: GiftUserRef?

    private var card: JSONValue? { m.card }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Sparkles().frame(height: 170)
                GiftBoxIcon(asset: plan.asset, size: 120)
            }
            .padding(.top, 6)
            Text(m.mine ? "Вы подарили" : "Подарок вам").font(.system(size: 26, weight: .heavy))
            Text("+ \(plan.titleFull)").font(.headline).foregroundStyle(Color.lime)
            (Text("Безлимитный ИИ-тренер, сканер еды и особое оформление в Oxion. ")
             + Text("Что даёт Premium ›").foregroundColor(Color.lime))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .onTapGesture { perks = true }

            VStack(spacing: 0) {
                person("От", id: Int(card?["from_id"]?.string ?? "") ?? (m.mine ? nil : m.fromId),
                       name: card?["from"]?.string ?? "Пользователь", photo: card?["from_photo"]?.string)
                Divider()
                person("Кому", id: Int(card?["to_id"]?.string ?? ""), name: card?["to"]?.string ?? "Пользователь", photo: card?["to_photo"]?.string)
                Divider()
                row("Дата", value: dateText(m.at))
                if let u = card?["until"]?.number {
                    Divider()
                    row("Действует до", value: dateText(u))
                }
            }
            .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Text("Тестовый режим: подарок активирован без оплаты").font(.caption).foregroundStyle(.secondary)

            Button { dismiss() } label: {
                Text("ОК").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime).foregroundStyle(Color.onLime)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .padding(16)
        }
        .background(Color.oxBg)
        .fitSheet()
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $perks) { PremiumView(embedded: true) }
        .sheet(item: $openUser) { u in NavigationStack { UserProfileView(userId: u.id) } }
    }

    private func dateText(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        let f = DateFormatter()
        f.locale = L10n.locale
        f.dateFormat = "dd.MM.yy 'в' HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms))
    }

    private func row(_ t: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(t).font(.subheadline).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func person(_ t: String, id: Int?, name: String, photo: String?) -> some View {
        Button {
            guard let id else { return }
            openUser = GiftUserRef(id: id)
        } label: {
            HStack(spacing: 0) {
                Text(t).font(.subheadline).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Avatar(url: API.media(photo), name: name, size: 24).padding(.trailing, 8)
                Text(name).font(.subheadline.bold()).foregroundStyle(Color.lime).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GiftUserRef: Identifiable { let id: Int }
