import SwiftUI

// MARK: - Корзина: общее состояние для кнопок «− 1 +» в карточках, товаре и корзине

@MainActor @Observable
final class ShopCart {
    static let shared = ShopCart()
    var count = 0
    var byVariant: [Int: Int] = [:]
    var byProduct: [Int: Int] = [:]
    var busy: Set<Int> = []

    func apply(_ c: MCart) {
        count = c.count
        var v: [Int: Int] = [:], p: [Int: Int] = [:]
        for it in c.stores.flatMap(\.items) {
            v[it.variantId, default: 0] += it.qty
            p[it.productId, default: 0] += it.qty
        }
        byVariant = v
        byProduct = p
    }

    func load() async {
        if let c: MCart = try? await API.call("/m/cart") { apply(c) }
    }

    /// Поставить количество варианта; 0 — убрать из корзины
    @discardableResult
    func set(variant: Int, qty: Int) async -> Bool {
        busy.insert(variant)
        defer { busy.remove(variant) }
        do {
            let c: MCart = try await API.call("/m/cart", method: "PUT", body: ["variant_id": variant, "qty": max(0, min(99, qty))])
            withAnimation(.snappy) { apply(c) }
            return true
        } catch {
            Haptic.error()
            OxAlert.error(error.localizedDescription)
            return false
        }
    }
}

/// Магазин спортпита: витрина, поиск, ИИ-подбор, магазины, карточки с кнопками корзины.
struct ShopView: View {
    @State private var home: ShopHome?
    @State private var errorText: String?
    @State private var query = ""
    @State private var results: [MProduct]?
    @State private var category: MCategory?
    @State private var catItems: [MProduct] = []
    @State private var catLoading = false
    @State private var openProduct: Int?
    @State private var openStore: MStoreShort?
    @State private var showCart = false
    @State private var showOrders = false
    @State private var showAI = false
    @State private var cart = ShopCart.shared

    private let grid = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let e = errorText, home == nil {
                    ErrorStateView(message: e) { Task { await load() } }
                        .padding(.top, 40)
                }
                if let r = results {
                    section("Найдено: \(r.count)") {
                        if r.isEmpty {
                            ContentUnavailableView.search(text: query)
                        } else { productGrid(r) }
                    }
                } else if let h = home {
                    aiBanner
                    if let cats = h.categories, !cats.isEmpty { categoriesBar(cats) }
                    if let c = category {
                        section(c.name) {
                            if catLoading {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                            } else if catItems.isEmpty {
                                ContentUnavailableView("Пока пусто", systemImage: "shippingbox", description: Text("В этой категории ещё нет товаров"))
                            } else { productGrid(catItems) }
                        }
                    } else {
                        if (h.activeOrders ?? 0) > 0 { ordersBanner(h.activeOrders ?? 0) }
                        if let fg = h.forGoal, !fg.isEmpty {
                            section("Под вашу цель") { productRow(fg) }
                        }
                        if let pop = h.popular, !pop.isEmpty {
                            section("Популярное") { productGrid(pop) }
                        }
                        if let stores = h.stores, !stores.isEmpty {
                            section("Магазины · \(h.city ?? "")") { storesList(stores) }
                        }
                        if (h.popular ?? []).isEmpty && (h.stores ?? []).isEmpty {
                            ContentUnavailableView("Магазинов пока нет", systemImage: "bag",
                                                   description: Text("В вашем городе ещё не подключены магазины спортпита"))
                        }
                    }
                } else if errorText == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, cart.count > 0 ? 100 : 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Магазин")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Протеин, креатин, бренд…")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { if query.isEmpty { results = nil } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCart = true } label: {
                    Image(systemName: "cart")
                        .overlay(alignment: .topTrailing) {
                            if cart.count > 0 {
                                Text("\(cart.count)")
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.lime, in: Capsule())
                                    .offset(x: 12, y: -10)
                                    .contentTransition(.numericText())
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if cart.count > 0 {
                Button { showCart = true } label: {
                    HStack {
                        Image(systemName: "cart.fill")
                        Text("Корзина")
                        Spacer()
                        Text("\(cart.count) " + RU.plural(cart.count, "товар", "товара", "товаров"))
                            .contentTransition(.numericText())
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 54)
                    .background(Color.lime, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: cart.count > 0)
        .navigationDestination(item: $openProduct) { id in
            ProductView(productId: id) { _ in }
        }
        .navigationDestination(item: $openStore) { s in
            StoreView(store: s) { openProduct = $0 }
        }
        .sheet(isPresented: $showCart) {
            CartView { _ in } onCheckout: {
                OxAlert.paymentsOff()
            }
        }
        .sheet(isPresented: $showAI) {
            ShopAIPickSheet { id in
                showAI = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openProduct = id }
            }
        }
        .navigationDestination(isPresented: $showOrders) { OrdersView() }
        .oxRefreshable { await load() }
        .task { if home == nil { await load() } }
    }

    // MARK: блоки

    private var aiBanner: some View {
        Button { showAI = true; Haptic.tap() } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(LinearGradient(colors: [Color(hex: 0x9B5CFF), Color(hex: 0x3B8CF5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Подобрать с ИИ").font(.headline)
                    Text("Опишите цель и бюджет — соберу набор из магазинов города")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func categoriesBar(_ cats: [MCategory]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cats) { c in
                    Button { Task { await pickCategory(c) } } label: {
                        HStack(spacing: 6) {
                            if let i = c.icon, !i.isEmpty { Text(i) }
                            Text(c.name)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(height: 36)
                        .foregroundStyle(category?.id == c.id ? Color.black : Color.primary)
                        .background(category?.id == c.id ? Color.lime : Color(.secondarySystemGroupedBackground), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func ordersBanner(_ n: Int) -> some View {
        Button { showOrders = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0x34C759), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("Активные заказы").font(.body.weight(.medium))
                Spacer()
                Text("\(n)").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func storesList(_ stores: [MStoreShort]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stores.enumerated()), id: \.element.id) { i, s in
                Button { openStore = s; Haptic.tap() } label: {
                    StoreRow(s: s)
                }
                .buttonStyle(.plain)
                if i < stores.count - 1 { Divider().padding(.leading, 78) }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal, 16)
            content()
        }
    }

    private func productGrid(_ items: [MProduct]) -> some View {
        LazyVGrid(columns: grid, spacing: 12) {
            ForEach(items) { p in
                ProductTile(p: p) { openProduct = p.id }
            }
        }
        .padding(.horizontal, 16)
    }

    private func productRow(_ items: [MProduct]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { p in
                    ProductTile(p: p) { openProduct = p.id }
                        .frame(width: 172)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func load() async {
        do {
            let h: ShopHome = try await API.call("/m/home")
            withAnimation(.snappy) { home = h }
            cart.count = h.cartCount ?? 0
            errorText = nil
            await cart.load()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func pickCategory(_ c: MCategory) async {
        Haptic.tap(.soft)
        if category?.id == c.id { withAnimation(.snappy) { category = nil }; return }
        withAnimation(.snappy) { category = c }
        catItems = []
        catLoading = true
        defer { catLoading = false }
        if let r: MCatalog = try? await API.call("/m/products", query: ["cat": String(c.id)]) {
            withAnimation(.snappy) { catItems = r.items }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = nil; return }
        if let r: MCatalog = try? await API.call("/m/products", query: ["q": q]) {
            results = r.items
        } else {
            results = []
        }
    }
}

struct StoreRow: View {
    let s: MStoreShort
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: API.media(s.logo), icon: "storefront.fill")
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if let d = s.description, !d.isEmpty {
                    Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let r = s.rating, r > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(String(format: "%.1f", r)).foregroundStyle(.secondary)
                }
                .font(.footnote.weight(.semibold))
            }
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Карточка товара: фото целиком, цена и «− 1 +» прямо в карточке

struct ProductTile: View {
    let p: MProduct
    var onOpen: () -> Void
    @State private var cart = ShopCart.shared
    @State private var pickVariant = false

    private var qty: Int { cart.byProduct[p.id] ?? p.cartQty ?? 0 }
    /// какой вариант двигаем кнопками: тот, что уже лежит в корзине, иначе вариант по умолчанию
    private var activeVariant: Int? {
        if let vs = p.variants, let v = vs.first(where: { (cart.byVariant[$0.id] ?? 0) > 0 }) { return v.id }
        return p.cartVariantId ?? p.variantId
    }
    private var multi: Bool { (p.variantsCount ?? 0) > 1 }
    private var soldOut: Bool { p.inStock == false || p.variantId == nil || (p.variantAvailable ?? 1) <= 0 && qty == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    photo
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(rub(p.priceKop)).font(.headline.monospacedDigit())
                            if let old = p.oldPriceKop, old > (p.priceKop ?? 0) {
                                Text(rub(old)).font(.caption).strikethrough().foregroundStyle(.secondary)
                            }
                        }
                        Text(p.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let b = p.brand, !b.isEmpty {
                                Text(b).lineLimit(1)
                            }
                            if let r = p.rating, r > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", r))
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: 16, alignment: .leading)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.plain)

            cartControl
                .padding(.top, 10)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(isPresented: $pickVariant) {
            VariantPickSheet(p: p).presentationDetents([.medium, .large])
        }
    }

    private var photo: some View {
        ZStack(alignment: .topLeading) {
            // фото целиком, без обрезки — как в магазинах: белая подложка
            Color.white
            RemoteImage(url: API.media(p.photo), icon: "takeoutbag.and.cup.and.straw.fill", fit: true)
                .padding(10)
            if let old = p.oldPriceKop, let now = p.priceKop, old > now {
                Text("−\(Int((1 - Double(now) / Double(old)) * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(hex: 0xFF3B30), in: Capsule())
                    .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if soldOut {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.35))
                Text("Нет в наличии").font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
    }

    @ViewBuilder private var cartControl: some View {
        let busy = activeVariant.map { cart.busy.contains($0) } ?? false
        if soldOut {
            Text("Нет в наличии")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(Color.primary.opacity(0.06), in: Capsule())
        } else if qty == 0 {
            Button {
                Haptic.tap(.medium)
                if multi { pickVariant = true; return }
                guard let v = activeVariant else { return }
                Task { await cart.set(variant: v, qty: 1) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: multi ? "plus" : "cart.badge.plus")
                    Text(multi ? "Выбрать вкус" : "В корзину")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(Color.lime, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy)
        } else {
            HStack(spacing: 0) {
                stepButton("minus") {
                    guard let v = activeVariant else { return }
                    let cur = cart.byVariant[v] ?? qty
                    Task { await cart.set(variant: v, qty: cur - 1) }
                }
                Spacer(minLength: 0)
                Group {
                    if busy { ProgressView().controlSize(.small) }
                    else {
                        Text("\(qty)")
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                .onTapGesture { if multi { pickVariant = true } }
                Spacer(minLength: 0)
                stepButton("plus") {
                    if multi && (cart.byVariant.keys.filter { k in (p.variants ?? []).contains { $0.id == k } }.count > 1) { pickVariant = true; return }
                    guard let v = activeVariant else { return }
                    let cur = cart.byVariant[v] ?? qty
                    Task { await cart.set(variant: v, qty: cur + 1) }
                }
            }
            .frame(height: 38)
            .background(Color.lime.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.lime.opacity(0.6), lineWidth: 1))
            .disabled(busy)
        }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.limeInk)
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Выбор вкуса/фасовки прямо из карточки, со своими кнопками «− +»
struct VariantPickSheet: View {
    let p: MProduct
    @Environment(\.dismiss) private var dismiss
    @State private var cart = ShopCart.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(p.variants ?? []) { v in
                        let q = cart.byVariant[v.id] ?? 0
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.label).font(.body.weight(.medium))
                                HStack(spacing: 6) {
                                    Text(rub(v.priceKop)).foregroundStyle(.secondary)
                                    if (v.available ?? 0) <= 0 { Text("нет в наличии").foregroundStyle(.red) }
                                    else if (v.available ?? 0) < 5 { Text("осталось \(v.available ?? 0)").foregroundStyle(.orange) }
                                }
                                .font(.subheadline)
                            }
                            Spacer()
                            if q == 0 {
                                Button {
                                    Haptic.tap(.medium)
                                    Task { await cart.set(variant: v.id, qty: 1) }
                                } label: {
                                    Image(systemName: "plus").font(.headline).foregroundStyle(.black)
                                        .frame(width: 36, height: 36).background(Color.lime, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled((v.available ?? 0) <= 0)
                            } else {
                                HStack(spacing: 14) {
                                    Button { Haptic.tap(.light); Task { await cart.set(variant: v.id, qty: q - 1) } } label: { Image(systemName: "minus") }
                                    Text("\(q)").font(.headline.monospacedDigit()).contentTransition(.numericText()).frame(minWidth: 20)
                                    Button { Haptic.tap(.light); Task { await cart.set(variant: v.id, qty: q + 1) } } label: { Image(systemName: "plus") }
                                        .disabled(q >= (v.available ?? 99))
                                }
                                .buttonStyle(.plain)
                                .font(.headline)
                                .foregroundStyle(Color.limeInk)
                                .padding(.horizontal, 12).frame(height: 36)
                                .background(Color.lime.opacity(0.18), in: Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(p.title)
                }
            }
            .navigationTitle("Вкус и фасовка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

// MARK: - Страница магазина

struct StoreView: View {
    let store: MStoreShort
    var onOpen: (Int) -> Void
    @State private var items: [MProduct] = []
    @State private var loading = true
    @State private var sort = "pop"
    private let grid = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    RemoteImage(url: API.media(store.logo), icon: "storefront.fill")
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    Text(store.name).font(.title2.bold())
                    if let r = store.rating, r > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(String(format: "%.1f", r)).bold()
                            Text("· \(store.ratingCount ?? 0) " + RU.plural(store.ratingCount ?? 0, "оценка", "оценки", "оценок"))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if let d = store.description, !d.isEmpty {
                        Text(d).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                }
                .padding(.top, 8)

                Picker("Сортировка", selection: $sort) {
                    Text("Популярные").tag("pop")
                    Text("Дешевле").tag("price")
                    Text("Рейтинг").tag("rating")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if loading {
                    ProgressView().padding(.top, 40)
                } else if items.isEmpty {
                    ContentUnavailableView("Товаров пока нет", systemImage: "shippingbox")
                } else {
                    LazyVGrid(columns: grid, spacing: 12) {
                        ForEach(items) { p in ProductTile(p: p) { onOpen(p.id) } }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sort) { await load() }
    }

    private func load() async {
        loading = items.isEmpty
        var q = ["store": String(store.id)]
        if sort != "pop" { q["sort"] = sort }
        if let r: MCatalog = try? await API.call("/m/products", query: q) {
            withAnimation(.snappy) { items = r.items }
        }
        loading = false
    }
}

// MARK: - ИИ-подбор

private struct AIPickResult: Decodable {
    let answer: String
    let items: [MProduct]
}

struct ShopAIPickSheet: View {
    var onOpen: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var asked = ""
    @State private var result: AIPickResult?
    @State private var loading = false
    @State private var errorText: String?
    @FocusState private var focused: Bool
    @State private var cart = ShopCart.shared

    private let ideas = ["Набрать массу, бюджет 3000 ₽", "Протеин без лактозы", "Что взять новичку", "Для выносливости и бега", "Похудеть без вреда", "Восстановление после тренировок"]
    private let grid = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if result == nil && !loading {
                        VStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(LinearGradient(colors: [Color(hex: 0x9B5CFF), Color(hex: 0x3B8CF5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            Text("ИИ-подбор спортпита").font(.title2.bold())
                            Text("Напишите цель, ограничения и бюджет. Подберу только то, что есть в магазинах вашего города.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Например").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                            FlowChipsWrap(items: ideas) { s in text = s; Task { await ask() } }
                        }
                    }
                    if !asked.isEmpty {
                        HStack {
                            Spacer(minLength: 40)
                            Text(asked)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .foregroundStyle(.black)
                                .background(Color.lime, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    if loading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Подбираю…").foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if let e = errorText {
                        Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.subheadline)
                    }
                    if let r = result {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles").foregroundStyle(Color(hex: 0x9B5CFF)).padding(.top, 2)
                            Text(r.answer).font(.body)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        if !r.items.isEmpty {
                            LazyVGrid(columns: grid, spacing: 12) {
                                ForEach(r.items) { p in ProductTile(p: p) { onOpen(p.id) } }
                            }
                            if r.items.contains(where: { (cart.byProduct[$0.id] ?? 0) == 0 && $0.inStock != false && ($0.variantsCount ?? 0) <= 1 && $0.variantId != nil }) {
                                Button {
                                    Task {
                                        for p in r.items where (cart.byProduct[p.id] ?? 0) == 0 && p.inStock != false && (p.variantsCount ?? 0) <= 1 {
                                            if let v = p.variantId { await cart.set(variant: v, qty: 1) }
                                        }
                                        Haptic.success()
                                    }
                                } label: {
                                    Label("Добавить всё в корзину", systemImage: "cart.badge.plus")
                                        .font(.headline).foregroundStyle(.black)
                                        .frame(maxWidth: .infinity).frame(height: 50)
                                        .background(Color.lime, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Подбор делает ИИ — проверьте состав. При болезнях и приёме лекарств посоветуйтесь с врачом.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField("Например: креатин и протеин до 4000 ₽", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button { Task { await ask() } } label: {
                        Image(systemName: "arrow.up").font(.headline).foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? Color.gray.opacity(0.4) : Color.lime, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(loading || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Подбор с ИИ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private func ask() async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3, !loading else { return }
        focused = false
        asked = q
        text = ""
        errorText = nil
        withAnimation(.snappy) { result = nil; loading = true }
        defer { loading = false }
        do {
            let r: AIPickResult = try await API.call("/m/ai/pick", method: "POST", body: ["text": q])
            Haptic.success()
            withAnimation(.snappy) { result = r }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Подсказки-капсулы с переносом строк
struct FlowChipsWrap: View {
    let items: [String]
    var onTap: (String) -> Void
    var body: some View {
        FlowLayoutSimple(spacing: 8) {
            ForEach(items, id: \.self) { s in
                Button { Haptic.tap(); onTap(s) } label: {
                    Text(s).font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayoutSimple: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing
            row = max(row, sz.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            row = max(row, sz.height)
        }
    }
}

struct ProductView: View {
    let productId: Int
    var onCart: (Int) -> Void

    @State private var p: MProductFull?
    @State private var variant: MVariant?
    @State private var qty = 1
    @State private var errorText: String?
    @State private var adding = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            if let p {
                VStack(alignment: .leading, spacing: 14) {
                    let photos = (p.photos ?? []).compactMap { API.media($0.url) }
                    if photos.isEmpty {
                        RemoteImage(url: nil, icon: "takeoutbag.and.cup.and.straw.fill").frame(height: 300)
                    } else {
                        TabView {
                            ForEach(photos, id: \.self) { u in
                                ZStack {
                                    Color.white
                                    RemoteImage(url: u, fit: true).padding(16)
                                }
                                .frame(height: 340)
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 340)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        if let b = p.brand, !b.isEmpty {
                            Text(b.uppercased()).font(.caption.bold()).foregroundStyle(Color.limeInk)
                        }
                        Text(p.title).font(.title2.bold())
                        HStack(spacing: 10) {
                            if let r = p.rating, r > 0 {
                                StatPill(icon: "star.fill", text: String(format: "%.1f · %ld", r, p.ratingCount ?? 0))
                            }
                            if let s = p.store?.name {
                                StatPill(icon: "storefront", text: s)
                            }
                        }
                        if p.variants.count > 1 {
                            Text("Вкус и объём").font(.headline).padding(.top, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(p.variants) { v in
                                        Button {
                                            variant = v
                                            Haptic.tap(.soft)
                                        } label: {
                                            VStack(spacing: 2) {
                                                Text(v.title.isEmpty ? "Вариант" : v.title).font(.subheadline.weight(.medium))
                                                Text(rub(v.priceKop)).font(.caption)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .foregroundStyle(variant?.id == v.id ? Color.black : Color.primary)
                                            .background(variant?.id == v.id ? Color.lime : Color.oxCard2, in: Capsule())
                                            .opacity((v.available ?? 0) > 0 ? 1 : 0.45)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if let d = p.description, !d.isEmpty { infoBlock("Описание", d) }
                        if let c = p.composition, !c.isEmpty { infoBlock("Состав", c) }
                        if let u = p.usage, !u.isEmpty { infoBlock("Как принимать", u) }
                        if let rs = p.reviews, !rs.isEmpty {
                            Text("Отзывы").font(.headline).padding(.top, 4)
                            ForEach(Array(rs.prefix(5).enumerated()), id: \.offset) { _, r in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(r.name ?? "Покупатель").font(.subheadline.bold())
                                        Spacer()
                                        Text(String(repeating: "★", count: Int(r.rating ?? 0))).foregroundStyle(.yellow)
                                    }
                                    if let t = r.text, !t.isEmpty { Text(t).font(.subheadline).foregroundStyle(Color.oxHint) }
                                }
                                .padding(12)
                                .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
            } else if let e = errorText {
                ErrorStateView(message: e) { Task { await load() } }.padding(.top, 60)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
            }
        }
        .background(Color.oxBg)
        .oxNoUnderlap()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let p {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleFav(p) }
                    } label: {
                        Image(systemName: p.fav == true ? "heart.fill" : "heart")
                            .foregroundStyle(p.fav == true ? Color.red : Color.primary)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let v = variant {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Button { qty = max(1, qty - 1) } label: { Image(systemName: "minus").frame(width: 40, height: 44) }
                        Text("\(qty)").font(.headline).frame(minWidth: 24)
                        Button { qty = min(99, qty + 1) } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    Button {
                        Task { await addToCart(v) }
                    } label: {
                        HStack {
                            if adding { ProgressView() }
                            Text((v.available ?? 0) > 0 ? "В корзину · \(rub((v.priceKop ?? 0) * qty))" : "Нет в наличии")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
                    .disabled(adding || (v.available ?? 0) == 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .toast($toast)
        .task { await load() }
    }

    private func infoBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(Color.oxHint)
        }
        .padding(.top, 4)
    }

    private func load() async {
        do {
            let r: MProductFull = try await API.call("/m/products/\(productId)")
            p = r
            variant = r.variants.first(where: { ($0.available ?? 0) > 0 }) ?? r.variants.first
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func addToCart(_ v: MVariant) async {
        adding = true
        defer { adding = false }
        do {
            // если товар уже в корзине — прибавляем к имеющемуся количеству
            let cur: MCart = try await API.call("/m/cart")
            let have = cur.stores.flatMap(\.items).first(where: { $0.variantId == v.id })?.qty ?? 0
            let c: MCart = try await API.call("/m/cart", method: "PUT", body: ["variant_id": v.id, "qty": min(99, have + qty)])
            onCart(c.count)
            ShopCart.shared.apply(c)
            Haptic.success()
            toast = "Добавлено в корзину"
        } catch {
            toast = error.localizedDescription
        }
    }

    private func toggleFav(_ p: MProductFull) async {
        let was = p.fav ?? false
        self.p?.fav = !was
        Haptic.tap()
        do {
            let _: OK = try await API.call("/m/products/\(p.id)/fav", method: was ? "DELETE" : "POST")
        } catch {
            self.p?.fav = was
        }
    }
}

struct CartView: View {
    var onCount: (Int) -> Void
    var onCheckout: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cart: MCart?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let c = cart {
                    if c.stores.isEmpty {
                        ContentUnavailableView("Корзина пуста", systemImage: "cart", description: Text("Добавьте товары из магазина"))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(c.stores) { st in
                        Section(st.storeName ?? "Магазин") {
                            ForEach(st.items) { it in
                                HStack(spacing: 12) {
                                    RemoteImage(url: API.media(it.photo), icon: "takeoutbag.and.cup.and.straw.fill")
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                        if let v = it.variant, !v.isEmpty { Text(v).font(.caption).foregroundStyle(Color.oxHint) }
                                        Text(rub(it.sumKop ?? (it.priceKop ?? 0) * it.qty)).font(.subheadline.bold())
                                        if let issue = it.issue { Text(issue).font(.caption).foregroundStyle(.red) }
                                    }
                                    Spacer()
                                    Stepper("", value: Binding(get: { it.qty }, set: { n in Task { await setQty(it.variantId, n) } }), in: 0...99)
                                        .labelsHidden()
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await setQty(it.variantId, 0) }
                                    } label: { Label("Убрать", systemImage: "trash") }
                                }
                            }
                            if let min = st.minOrderKop, min > 0, (st.itemsKop ?? 0) < min {
                                Text("Минимальный заказ в этом магазине — \(rub(min))")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } else if let e = errorText {
                    ErrorStateView(message: e) { Task { await load() } }.listRowBackground(Color.clear)
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Корзина")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                if let c = cart, !c.stores.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Очистить") { Task { await clear() } }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let c = cart, c.count > 0 {
                    Button {
                        onCheckout()
                    } label: {
                        Text("Оформить · \(rub(c.itemsKop))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let c: MCart = try await API.call("/m/cart")
            cart = c
            onCount(c.count)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func setQty(_ vid: Int, _ qty: Int) async {
        do {
            let c: MCart = try await API.call("/m/cart", method: "PUT", body: ["variant_id": vid, "qty": qty])
            cart = c
            onCount(c.count)
            ShopCart.shared.apply(c)
            Haptic.tap(.soft)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func clear() async {
        if let c: MCart = try? await API.call("/m/cart", method: "DELETE") {
            cart = c
            ShopCart.shared.apply(c)
            onCount(c.count)
        }
    }
}
