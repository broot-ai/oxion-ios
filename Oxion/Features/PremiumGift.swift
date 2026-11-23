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
        case "red": Color(hex: 0xFF4D5E)
        default: Color(hex: 0x4CD964)
        }
    }
    var priceText: String { "\(price.formatted(.number.locale(Locale(identifier: "ru_RU")))) ₽" }
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
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "d MMMM yyyy"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
}

// MARK: - Коробка подарка

/// Нарисованная коробка с бантом и звездой — цвет по тарифу
struct GiftBoxIcon: View {
    var tint: Color
    var size: CGFloat = 64
    @State private var float = false

    var body: some View {
        ZStack {
            // крышка + коробка
            VStack(spacing: size * 0.02) {
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.86, height: size * 0.2)
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.3)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.74, height: size * 0.44)
            }
            .overlay {
                // лента
                Rectangle().fill(Color(hex: 0xFFD54A)).frame(width: size * 0.13)
                    .offset(y: size * 0.01)
            }
            .offset(y: size * 0.16)
            // звезда сверху
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFE680), Color(hex: 0xFFB000)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: 0xFFB000).opacity(0.6), radius: size * 0.08)
                .offset(y: -size * 0.2 + (float ? -size * 0.04 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { float = true }
        }
    }
}

/// Мерцающие звёздочки вокруг аватарки
private struct Sparkles: View {
    var color: Color = Color(hex: 0xFFC53D)
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for i in 0..<26 {
                    let fi = Double(i)
                    let x = (sin(fi * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let y = (sin(fi * 78.233) * 12345.6789).truncatingRemainder(dividingBy: 1)
                    let px = abs(x) * size.width
                    let py = abs(y) * size.height
                    let a = 0.25 + 0.75 * abs(sin(t * (0.8 + fi.truncatingRemainder(dividingBy: 5) * 0.3) + fi))
                    let r = 1.5 + fi.truncatingRemainder(dividingBy: 3) * 1.2
                    var c = ctx
                    c.opacity = a
                    c.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)), with: .color(i % 4 == 0 ? .white : color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Панель «Подарить Premium» (вкладка «Подарок» в чате)

struct GiftPremiumPanel: View {
    let userId: Int
    var name: String
    var photo: String?
    var onSent: (Int?) -> Void = { _ in }

    @State private var info: PremiumInfo?
    @State private var error: String?
    @State private var pick: PremiumPlan?
    @State private var showPerks = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ZStack {
                    Sparkles().frame(height: 150).padding(.horizontal, 30)
                    Avatar(url: API.media(photo ?? info?.to?.photo), name: name, size: 96)
                        .shadow(color: Color(hex: 0xFFC53D).opacity(0.35), radius: 20)
                }
                .padding(.top, 8)

                Text("Подарить Premium").font(.system(size: 26, weight: .heavy))
                (Text("Подарите **\(name)** доступ к эксклюзивным функциям Oxion. ")
                 + Text("Подробнее о Premium ›").foregroundColor(Color.lime))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .onTapGesture { showPerks = true }

                if let until = info?.to?.premiumUntil {
                    Label("У \(name) уже есть Premium до \(untilText(until)) — подарок продлит его", systemImage: "star.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: 0xFFC53D))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(hex: 0xFFC53D).opacity(0.12), in: Capsule())
                }

                if let plans = info?.plans {
                    HStack(spacing: 10) {
                        ForEach(plans) { p in
                            PlanCard(plan: p) { pick = p }
                        }
                    }
                    .padding(.horizontal, 14)
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
                .padding(.top, 14)
            }
            .padding(.bottom, 110)
        }
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
        .sheet(isPresented: $showPerks) { NavigationStack { PremiumView(embedded: true) } }
    }
}

private struct PlanCard: View {
    let plan: PremiumPlan
    var tap: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: { Haptic.tap(); tap() }) {
            VStack(spacing: 6) {
                GiftBoxIcon(tint: plan.tint, size: 58).padding(.top, 10)
                Text(plan.title).font(.subheadline.bold()).foregroundStyle(.primary)
                Text("Premium").font(.caption).foregroundStyle(.secondary)
                Text(plan.priceText)
                    .font(.caption.bold())
                    .foregroundStyle(Color.lime)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.lime.opacity(0.14), in: Capsule())
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let d = plan.discount, d > 0 {
                    Text("−\(d)%")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 16)
                        .background(Color(hex: 0x9B5CFF))
                        .rotationEffect(.degrees(45))
                        .offset(x: 20, y: 10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            .padding(.horizontal, 16).padding(.top, 14)

            ScrollView {
                VStack(spacing: 14) {
                    Text("Вы отправляете подарок за \(plan.priceText)")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())

                    VStack(spacing: 8) {
                        GiftBoxIcon(tint: plan.tint, size: 110)
                            .padding(.top, 14)
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
                    .frame(width: 220)
                    .padding(.horizontal, 10)
                    .background(
                        LinearGradient(colors: [plan.tint.opacity(0.28), Color.oxCard], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(plan.tint.opacity(0.35)))

                    TextField("Ваше сообщение (необязательно)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focus)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onChange(of: note) { if note.count > 200 { note = String(note.prefix(200)) } }

                    Label("Тестовый режим: подарок активируется сразу, деньги не списываются", systemImage: "testtube.2")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)

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
        .presentationDetents([.large])
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
            GiftBoxIcon(tint: plan.tint, size: 96).padding(.top, 18)
            Text(plan.titleFull).font(.headline).foregroundStyle(.white)
            Text(mine ? "Вы подарили \(card?["to"]?.string ?? "собеседнику") подписку Oxion Premium"
                      : "\(card?["from"]?.string ?? "Собеседник") дарит вам подписку Oxion Premium")
                .font(.caption).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            if let n = card?["note"]?.string, !n.isEmpty {
                Text("«\(n)»").font(.subheadline.italic()).foregroundStyle(.white).multilineTextAlignment(.center)
            }
            Button(mine ? "Подробнее" : "Посмотреть возможности") { showPerks = true }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(.white.opacity(0.16), in: Capsule())
                .buttonStyle(.plain)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [plan.tint.opacity(0.55), Color(hex: 0x15161A)], startPoint: .top, endPoint: .bottom)
                Sparkles(color: .white).opacity(0.6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(plan.tint.opacity(0.5)))
        .sheet(isPresented: $showPerks) { NavigationStack { PremiumView(embedded: true) } }
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
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Sparkles().frame(height: 150)
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 84))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFE680), Color(hex: 0xFFB000)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color(hex: 0xFFB000).opacity(0.5), radius: 24)
                        .symbolEffect(.bounce, value: info?.active)
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
            .padding(.bottom, embedded ? 20 : 100)
        }
        .background(Color.oxBg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedded {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !embedded, let p = plan {
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
            OxHaptics.play(.workoutDone)
            OxAlert.show(icon: "star.circle.fill", tint: Color(hex: 0xFFB000), title: "Premium подключён", message: "Тестовый режим — без списания денег")
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}
