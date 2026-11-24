import SwiftUI
import EventKit
import EventKitUI
import MapKit

// MARK: - Запись к тренеру: окна тренера, запись клиента, отмена, календарь, главный экран

struct Slot: Decodable, Identifiable, Hashable {
    let id: Int
    let startsAt: Double
    let minutes: Int?
    let place: String?
    let price: Int?
    let status: String?
    let note: String?
    let client: SlotClient?

    var date: Date { Date(timeIntervalSince1970: startsAt / 1000) }
    var end: Date { date.addingTimeInterval(Double(minutes ?? 60) * 60) }
}
struct SlotClient: Decodable, Hashable { let id: Int; let name: String? }
struct SlotsResponse: Decodable { let items: [Slot]; let link: String? }
struct CoachSlotsResponse: Decodable { let items: [Slot] }
struct LinkResult: Decodable { let ok: Bool?; let status: String? }

extension CoachBooking {
    var date: Date { Date(timeIntervalSince1970: (startsAt ?? 0) / 1000) }
}

enum BookingFormat {
    static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "EEEE, d MMMM"; return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "HH:mm"; return f
    }()
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let t = time.string(from: d)
        if cal.isDateInToday(d) { return "Сегодня в \(t)" }
        if cal.isDateInTomorrow(d) { return "Завтра в \(t)" }
        return day.string(from: d).capitalized + " в " + t
    }
    static func relative(_ d: Date) -> String {
        let s = d.timeIntervalSinceNow
        if s < 0 { return "уже идёт" }
        if s < 3600 { return "через \(max(1, Int(s / 60))) мин" }
        if s < 86400 { return "через \(Int(s / 3600)) ч \(Int(s.truncatingRemainder(dividingBy: 3600) / 60)) мин" }
        return "через \(Int(s / 86400)) дн."
    }
}

/// Добавить занятие в «Календарь» (системное окно — пользователь сам подтверждает)
@MainActor
enum CalendarAdd {
    private static let store = EKEventStore()
    private final class Delegate: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(_ c: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            c.dismiss(animated: true)
            if action == .saved { Haptic.success() }
        }
    }
    private static let delegate = Delegate()

    static func add(title: String, start: Date, minutes: Int, place: String?) {
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(minutes) * 60)
        e.location = place
        e.addAlarm(EKAlarm(relativeOffset: -3600))
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = e
        vc.editViewDelegate = delegate
        GameHub.topController()?.present(vc, animated: true)
    }
}

// MARK: Запись клиента

struct BookingSheet: View {
    let trainerId: Int
    let trainerName: String
    var onBooked: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var slots: [Slot] = []
    @State private var link: String?
    @State private var loaded = false
    @State private var day: Date?
    @State private var chosen: Slot?
    @State private var note = ""
    @State private var busy = false
    @State private var done: Slot?
    @Namespace private var ns

    private var days: [Date] {
        let cal = Calendar.current
        return Array(Set(slots.map { cal.startOfDay(for: $0.date) })).sorted()
    }
    private var daySlots: [Slot] {
        guard let day else { return [] }
        return slots.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let done { success(done) }
                else if !loaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if slots.isEmpty { empty }
                else { picker }
            }
            .background(Color.oxBg)
            .navigationTitle(done == nil ? "Запись к тренеру" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(34)
        .task { await load() }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "calendar.badge.clock").font(.system(size: 54)).foregroundStyle(Color.limeInk)
            Text("Свободных окон пока нет").font(.title3.bold())
            Text("\(trainerName) ещё не открыл(а) время для записи. Напишите тренеру — договоритесь лично.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 30)
            linkButton
            Spacer()
        }
    }

    @ViewBuilder
    private var linkButton: some View {
        if link == nil {
            Button {
                Task { await requestLink() }
            } label: {
                Label("Стать клиентом \(trainerName)", systemImage: "person.badge.plus").font(.headline).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        } else {
            Label(link == "active" ? "Вы клиент этого тренера" : "Заявка отправлена — тренер подтвердит",
                  systemImage: link == "active" ? "checkmark.seal.fill" : "hourglass")
                .font(.subheadline.bold())
                .foregroundStyle(link == "active" ? Color.limeInk : Color.secondary)
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill").foregroundStyle(Color.limeInk)
                    Text(trainerName).font(.headline)
                    Spacer()
                    Text("\(slots.count) \(RU.plural(slots.count, "окно", "окна", "окон"))").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                // дни
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.self) { d in
                            let on = day.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false
                            Button {
                                Haptic.tap()
                                withAnimation(.spring(duration: 0.35)) { day = d; chosen = nil }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(d.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))).uppercased())
                                        .font(.caption2.bold())
                                    Text(d.formatted(.dateTime.day())).font(.title3.bold())
                                    Text("\(slots.filter { Calendar.current.isDate($0.date, inSameDayAs: d) }.count)")
                                        .font(.caption2).opacity(0.7)
                                }
                                .foregroundStyle(on ? Color.onLime : .primary)
                                .frame(width: 58, height: 78)
                                .background {
                                    if on { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.lime).matchedGeometryEffect(id: "day", in: ns) }
                                }
                                .glassEffect(on ? .identity : .regular.interactive(), in: .rect(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // время
                if let day {
                    Text(BookingFormat.day.string(from: day).capitalized).font(.headline).padding(.horizontal, 16)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(daySlots) { s in
                            let on = chosen?.id == s.id
                            Button {
                                Haptic.tap()
                                withAnimation(.spring(duration: 0.3, bounce: 0.4)) { chosen = s }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(BookingFormat.time.string(from: s.date)).font(.headline.monospacedDigit())
                                    Text("\(s.minutes ?? 60) мин").font(.caption2).opacity(0.7)
                                }
                                .foregroundStyle(on ? Color.onLime : .primary)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(on ? Color.lime : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .glassEffect(on ? .identity : .regular.interactive(), in: .rect(cornerRadius: 16))
                                .scaleEffect(on ? 1.04 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if let s = chosen {
                    VStack(alignment: .leading, spacing: 10) {
                        detail("clock", BookingFormat.when(s.date) + " · \(s.minutes ?? 60) мин")
                        if let p = s.place, !p.isEmpty { detail("mappin.and.ellipse", p) }
                        detail("rublesign", s.price.map { $0 == 0 ? "Бесплатно" : "\($0) ₽ — оплата тренеру на месте" } ?? "Цену уточните у тренера")
                        TextField("Комментарий тренеру (необязательно)", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(12)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(16)
                    .oxCardBG(24)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                linkButton.frame(maxWidth: .infinity).padding(.top, 4)
                Text("Отменить запись можно в «Мой тренер». Лучше — не позже чем за 12 часов.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 100)
            }
            .padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await book() }
            } label: {
                HStack {
                    if busy { ProgressView() }
                    Text(chosen.map { "Записаться · " + BookingFormat.when($0.date) } ?? "Выберите время")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime)
            .foregroundStyle(Color.onLime)
            .disabled(chosen == nil || busy)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func detail(_ icon: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Color.limeInk) }
            .font(.subheadline)
    }

    private func success(_ s: Slot) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(Color.lime)
                .symbolEffect(.bounce, value: done?.id)
            Text("Вы записаны!").font(.title.bold())
            Text("\(trainerName)\n\(BookingFormat.when(s.date))\(s.place.map { "\n\($0)" } ?? "")")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Тренер получил уведомление. За 2 часа OXION напомнит о занятии.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            Button {
                CalendarAdd.add(title: "Тренировка с \(trainerName)", start: s.date, minutes: s.minutes ?? 60, place: s.place)
            } label: {
                Label("Добавить в Календарь", systemImage: "calendar.badge.plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            Button { dismiss() } label: {
                Text("Готово").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
        }
        .padding(20)
    }

    private func load() async {
        do {
            let r: SlotsResponse = try await API.call("/trainers/\(trainerId)/slots")
            slots = r.items.sorted { $0.startsAt < $1.startsAt }
            link = r.link
            day = days.first
        } catch { OxAlert.error(error.localizedDescription) }
        loaded = true
    }

    private func requestLink() async {
        do {
            let r: LinkResult = try await API.call("/coach/link/\(trainerId)", method: "POST", body: [:])
            withAnimation { link = r.status ?? "pending" }
            Haptic.success()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func book() async {
        guard let s = chosen else { return }
        busy = true
        defer { busy = false }
        do {
            let _: OK = try await API.call("/coach/slots/\(s.id)/book", method: "POST", body: ["note": note])
            if link == nil { await requestLink() }
            withAnimation(.spring(duration: 0.5)) { done = s }
            FX.play(.confetti)
            onBooked()
            BookingStore.shared.refresh()
        } catch {
            OxAlert.error(error.localizedDescription)
            await load()
        }
    }
}

// MARK: Общие данные для главного экрана

@MainActor
@Observable
final class BookingStore {
    static let shared = BookingStore()
    var my: CoachMy?
    var trainerSlots: [Slot] = []
    var pendingClients = 0

    var next: CoachBooking? { (my?.bookings ?? []).filter { $0.date.addingTimeInterval(Double($0.minutes ?? 60) * 60) > Date() }.min { $0.date < $1.date } }
    var mainTrainer: CoachTrainer? { (my?.trainers ?? []).first { $0.status == "active" } ?? my?.trainers?.first }

    func refresh() {
        Task {
            my = try? await API.call("/coach/my")
        }
    }

    func refreshTrainer() {
        Task {
            if let r: CoachSlotsResponse = try? await API.call("/coach/slots") { trainerSlots = r.items }
            if let c: ClientsResponse = try? await API.call("/coach/clients") { pendingClients = c.items.filter { $0.status == "pending" }.count }
        }
    }

    func cancel(_ id: Int, late: Bool) async -> Bool {
        do {
            let _: OK = try await API.call("/coach/slots/\(id)", method: "DELETE")
            Haptic.success()
            refresh()
            refreshTrainer()
            return true
        } catch {
            OxAlert.error(error.localizedDescription)
            return false
        }
    }
}

/// Карточка на главной: ближайшее занятие с тренером / записаться / найти тренера
struct HomeSessionCard: View {
    @Environment(AppModel.self) private var model
    @State private var store = BookingStore.shared
    @State private var booking: (Int, String)?
    @State private var chat: ChatRef?
    var openTrainer: (Int) -> Void

    var body: some View {
        Group {
            if let b = store.next {
                upcoming(b)
            } else if let t = store.mainTrainer {
                cta(icon: "calendar.badge.plus", title: "Записаться на тренировку", sub: "к \(t.name ?? "тренеру")") {
                    booking = (t.id, t.name ?? "Тренер")
                }
            } else if store.my != nil {
                cta(icon: "figure.strengthtraining.traditional", title: "Найти своего тренера", sub: "Запись на занятия, план и контроль прогресса") {
                    model.selectedTab = .trainers
                }
            }
        }
        .onAppear { store.refresh() }
        .sheet(isPresented: Binding(get: { booking != nil }, set: { if !$0 { booking = nil } })) {
            if let b = booking { BookingSheet(trainerId: b.0, trainerName: b.1) }
        }
        .navigationDestination(item: $chat) { ChatView(chatId: $0.id, title: $0.name) }
    }

    private func upcoming(_ b: CoachBooking) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Ближайшее занятие", systemImage: "calendar").font(.caption.bold()).foregroundStyle(Color.limeInk)
                    Spacer()
                    Text(BookingFormat.relative(b.date))
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.lime.opacity(0.18), in: Capsule())
                }
                Text(BookingFormat.when(b.date)).font(.title3.bold())
                Text([b.trainer?.name, b.place, "\(b.minutes ?? 60) мин"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    small("Написать", "bubble.left.fill") { Task { await openChat(b) } }
                    if let p = b.place, !p.isEmpty {
                        small("Маршрут", "map.fill") {
                            if let u = URL(string: "maps://?q=\(p.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") { UIApplication.shared.open(u) }
                        }
                    }
                    small("Календарь", "calendar.badge.plus") {
                        CalendarAdd.add(title: "Тренировка с \(b.trainer?.name ?? "тренером")", start: b.date, minutes: b.minutes ?? 60, place: b.place)
                    }
                    Spacer(minLength: 0)
                    Button(role: .destructive) { confirmCancel(b) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.glass)
                }
            }
            .padding(16)
            .background(
                LinearGradient(colors: [Color.lime.opacity(0.16), Color.oxCard], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private func small(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { Haptic.tap(); action() }) {
            Label(t, systemImage: icon).font(.caption.bold()).lineLimit(1)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    private func cta(icon: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.onLime)
                    .frame(width: 50, height: 50)
                    .background(Color.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(16)
            .oxCardBG(24)
        }
        .buttonStyle(.plain)
    }

    private func confirmCancel(_ b: CoachBooking) {
        let late = b.date.timeIntervalSinceNow < 12 * 3600
        OxAlert.confirm(icon: "calendar.badge.minus", title: "Отменить запись?",
                        message: late ? "До занятия меньше 12 часов — тренер увидит позднюю отмену." : BookingFormat.when(b.date),
                        action: "Отменить запись", destructive: true) {
            Task { _ = await store.cancel(b.id, late: late) }
        }
    }

    private func openChat(_ b: CoachBooking) async {
        guard let id = b.trainer?.id else { return }
        do {
            let r: IdResponse = try await API.call("/chats/open", method: "POST", body: ["user_id": id])
            chat = ChatRef(id: r.id, name: b.trainer?.name ?? "Тренер")
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: Тренер: расписание (окна для записи)

struct TrainerScheduleView: View {
    @State private var store = BookingStore.shared
    @State private var adding = false

    private var grouped: [(Date, [Slot])] {
        let cal = Calendar.current
        let g = Dictionary(grouping: store.trainerSlots.filter { $0.status != "cancelled" }) { cal.startOfDay(for: $0.date) }
        return g.keys.sorted().map { ($0, g[$0]!.sorted { $0.startsAt < $1.startsAt }) }
    }

    var body: some View {
        List {
            if grouped.isEmpty {
                ContentUnavailableView("Окон пока нет", systemImage: "calendar.badge.plus",
                                       description: Text("Откройте время — клиенты смогут записаться прямо из вашей анкеты"))
                    .listRowBackground(Color.clear)
            }
            ForEach(grouped, id: \.0) { day, items in
                Section(BookingFormat.day.string(from: day).capitalized) {
                    ForEach(items) { s in
                        HStack(spacing: 12) {
                            Text(BookingFormat.time.string(from: s.date))
                                .font(.headline.monospacedDigit())
                                .frame(width: 58, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.status == "booked" ? (s.client?.name ?? "Клиент") : "Свободно")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(s.status == "booked" ? Color.primary : Color.limeInk)
                                Text([s.place, "\(s.minutes ?? 60) мин", s.price.map { "\($0) ₽" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let n = s.note, !n.isEmpty { Text("«\(n)»").font(.caption).italic() }
                            }
                            Spacer()
                            Image(systemName: s.status == "booked" ? "person.fill.checkmark" : "circle.dashed")
                                .foregroundStyle(s.status == "booked" ? Color.limeInk : .secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { _ = await store.cancel(s.id, late: false) }
                            } label: { Label(s.status == "booked" ? "Отменить" : "Удалить", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Расписание")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) { AddSlotsSheet { store.refreshTrainer() } }
        .oxRefreshable { store.refreshTrainer() }
        .onAppear { store.refreshTrainer() }
    }
}

struct AddSlotsSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
    @State private var times: Set<Int> = []        // минуты от полуночи
    @State private var minutes = 60
    @State private var price = ""
    @State private var place = ""
    @State private var repeatWeeks = 1
    @State private var busy = false

    private let grid = Array(stride(from: 7 * 60, through: 22 * 60, by: 60))

    var body: some View {
        NavigationStack {
            Form {
                Section("День") {
                    DatePicker("Дата", selection: $date, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color.limeInk)
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(grid, id: \.self) { m in
                            let on = times.contains(m)
                            Button {
                                Haptic.tap()
                                if on { times.remove(m) } else { times.insert(m) }
                            } label: {
                                Text(String(format: "%02d:%02d", m / 60, m % 60))
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(on ? Color.onLime : .primary)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(on ? Color.lime : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Время начала")
                } footer: {
                    Text("Выберите несколько часов — создастся окно на каждый.")
                }
                Section("Параметры") {
                    Picker("Длительность", selection: $minutes) {
                        ForEach([30, 45, 60, 90, 120], id: \.self) { Text("\($0) мин").tag($0) }
                    }
                    TextField("Цена, ₽ (необязательно)", text: $price).keyboardType(.numberPad)
                    TextField("Место: зал, адрес или «онлайн»", text: $place)
                    Stepper("Повторить: \(repeatWeeks) \(RU.plural(repeatWeeks, "неделя", "недели", "недель"))", value: $repeatWeeks, in: 1...8)
                }
            }
            .navigationTitle("Новые окна")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "…" : "Создать") { Task { await save() } }.disabled(times.isEmpty || busy)
                }
            }
        }
    }

    private struct Created: Decodable { let created: Int?; let skipped: Int? }

    private func save() async {
        busy = true
        defer { busy = false }
        var starts: [Double] = []
        for w in 0..<repeatWeeks {
            let d = date.addingTimeInterval(Double(w) * 7 * 86400)
            for m in times.sorted() {
                let t = d.addingTimeInterval(Double(m) * 60)
                if t > Date() { starts.append(t.timeIntervalSince1970 * 1000) }
            }
        }
        var body: [String: Any] = ["starts": Array(starts.prefix(40)), "minutes": minutes]
        if let p = Int(price) { body["price"] = p }
        if !place.isEmpty { body["place"] = place }
        do {
            let r: Created = try await API.call("/coach/slots", method: "POST", body: body)
            Haptic.success()
            OxAlert.show(icon: "calendar.badge.checkmark", title: "Создано окон: \(r.created ?? 0)",
                         message: (r.skipped ?? 0) > 0 ? "Пропущено \(r.skipped!) — пересекаются с уже открытыми" : "")
            onDone()
            dismiss()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

/// Тренер на главной: ближайший клиент и заявки
struct HomeTrainerCard: View {
    @State private var store = BookingStore.shared
    var body: some View {
        let today = store.trainerSlots.filter { $0.status == "booked" && $0.date > Date().addingTimeInterval(-3600) }.sorted { $0.startsAt < $1.startsAt }
        VStack(spacing: 8) {
        NavigationLink { TrainerScheduleView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Расписание", systemImage: "calendar").font(.caption.bold()).foregroundStyle(Color.limeInk)
                    Spacer()
                }
                if let s = today.first {
                    Text(BookingFormat.when(s.date)).font(.title3.bold())
                    Text("\(s.client?.name ?? "Клиент") · \(s.minutes ?? 60) мин\(s.place.map { " · \($0)" } ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if today.count > 1 { Text("ещё \(today.count - 1) \(RU.plural(today.count - 1, "занятие", "занятия", "занятий"))").font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("Нет записей").font(.title3.bold())
                    Text("Откройте окна — клиенты запишутся из вашей анкеты").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color.lime.opacity(0.14), Color.oxCard], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
            if store.pendingClients > 0 {
                NavigationLink { InboxView() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus").font(.title3).foregroundStyle(Color.limeInk)
                        Text("Новые заявки: \(store.pendingClients)").font(.subheadline.bold())
                        Spacer()
                        Text("Посмотреть").font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.lime.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { store.refreshTrainer() }
    }
}
