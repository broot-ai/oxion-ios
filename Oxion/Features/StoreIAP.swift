import SwiftUI
import StoreKit

/// Подписка PRO через App Store (StoreKit 2).
/// Покупку проверяет сервер: приложение отправляет подписанную Apple транзакцию (JWS) на /iap/apple.
/// Работает только в сборке с платным аккаунтом разработчика (TestFlight / App Store).
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()
    static let productId = "ru.oxion.app.pro.month"

    var product: Product?
    var loaded = false
    var busy = false
    var activeUntil: Date?
    /// PRO получен от организатора «Семейного доступа», а не куплен самим пользователем
    var familyShared = false
    /// Подписку можно разделить с семьёй (включается в App Store Connect у продукта)
    var familyShareable: Bool { product?.isFamilyShareable ?? false }
    private var listener: Task<Void, Never>?

    private struct IapReply: Decodable { let ok: Bool?; let expiresAt: Double?; let paidUntil: Double? }

    /// Слушать продления и возвраты, которые приходят без участия пользователя
    func start() {
        guard listener == nil else { return }
        listener = Task {
            for await update in StoreKit.Transaction.updates {
                await self.handle(update)
            }
        }
    }

    func load() async {
        start()
        product = try? await Product.products(for: [Self.productId]).first
        loaded = true
        for await r in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = r, t.productID == Self.productId, t.revocationDate == nil {
                activeUntil = t.expirationDate
                familyShared = t.ownershipType == .familyShared
            }
        }
    }

    @discardableResult
    func buy() async -> Bool {
        if product == nil { await load() }
        guard let product else {
            OxAlert.show(icon: "bag.badge.questionmark", tint: .orange, title: "Покупка недоступна",
                         message: "Эта сборка установлена без App Store. Оплата через Apple работает в версии из TestFlight или App Store.")
            return false
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let v):
                return await handle(v)
            case .pending:
                OxAlert.show(icon: "hourglass", title: "Покупка ожидает подтверждения", message: "Например, одобрения через «Семейный доступ».")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            OxAlert.error(error.localizedDescription)
        }
        return false
    }

    func restore() async {
        busy = true
        defer { busy = false }
        do { try await AppStore.sync() } catch { OxAlert.error(error.localizedDescription); return }
        var found = false
        for await r in StoreKit.Transaction.currentEntitlements where r.unsafePayloadValue.productID == Self.productId {
            found = await handle(r) || found
        }
        OxAlert.show(icon: found ? "checkmark.seal.fill" : "info.circle.fill",
                     title: found ? "Покупки восстановлены" : "Активной подписки нет")
    }

    /// Отправить транзакцию на сервер и завершить её
    @discardableResult
    private func handle(_ r: VerificationResult<StoreKit.Transaction>) async -> Bool {
        guard case .verified(let t) = r else { return false }
        do {
            let reply: IapReply = try await API.call("/iap/apple", method: "POST",
                                                     body: ["jws": r.jwsRepresentation, "family": t.ownershipType == .familyShared])
            activeUntil = t.expirationDate
            familyShared = t.ownershipType == .familyShared
            await t.finish()
            return reply.ok == true
        } catch {
            // сервер недоступен — не завершаем транзакцию, StoreKit пришлёт её снова
            return false
        }
    }
}

/// Блок покупки для экрана PRO
struct ProPurchaseBlock: View {
    @State private var store = ProStore.shared
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Button {
                Task { if await store.buy() { onDone() } }
            } label: {
                HStack(spacing: 8) {
                    if store.busy { ProgressView() } else { Image(systemName: "apple.logo") }
                    Text(store.product.map { "Оформить через App Store · \($0.displayPrice)" } ?? "Оформить через App Store")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.7)
            .disabled(store.busy)

            if store.familyShared {
                Label("PRO доступен через «Семейный доступ»", systemImage: "person.3.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.limeInk)
            } else if store.familyShareable {
                Label("Можно разделить с семьёй — до 5 человек в «Семейном доступе»", systemImage: "person.3")
                    .font(.caption).foregroundStyle(Color.oxHint)
            }
            HStack {
                if let until = store.activeUntil {
                    Text("Подписка до \(until.formatted(date: .abbreviated, time: .omitted))")
                }
                Spacer()
                Button("Восстановить покупки") { Task { await store.restore() } }
            }
            .font(.caption)
            .foregroundStyle(Color.oxHint)
        }
        .task { if !store.loaded { await store.load() } }
    }
}
