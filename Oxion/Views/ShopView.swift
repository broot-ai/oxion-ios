import SwiftUI

/// Магазин спортпита: витрина, поиск, карточка товара, корзина. Оформление заказа — через веб-версию
/// (адреса, доставка, оплата ЮKassa), всё остальное — родное.
struct ShopView: View {
    @State private var home: ShopHome?
    @State private var errorText: String?
    @State private var query = ""
    @State private var results: [MProduct]?
    @State private var category: MCategory?
    @State private var catItems: [MProduct] = []
    @State private var openProduct: Int?
    @State private var showCart = false
    @State private var cartCount = 0
    @State private var web: WebTarget?

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let e = errorText, home == nil {
                    ErrorStateView(message: e) { Task { await load() } }
                        .padding(.top, 40)
                }
                if let r = results {
                    sectionTitle("Найдено: \(r.count)")
                    productGrid(r)
                } else if let h = home {
                    if let cats = h.categories, !cats.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(cats) { c in
                                    Button {
                                        Task { await pickCategory(c) }
                                    } label: {
                                        Chip(text: "\(c.icon ?? "") \(c.name)", selected: category?.id == c.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    if let c = category {
                        sectionTitle(c.name)
                        if catItems.isEmpty {
                            Text("В этой категории пока нет товаров")
                                .foregroundStyle(Color.oxHint)
                                .padding(.horizontal, 16)
                        } else {
                            productGrid(catItems)
                        }
                    } else {
                        if (h.activeOrders ?? 0) > 0 {
                            Button {
                                web = WebTarget(path: "/#morders")
                            } label: {
                                HStack {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(Color.lime)
                                    Text("Активные заказы: \(h.activeOrders ?? 0)")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(16)
                                .glassEffect(.regular.tint(Color.lime.opacity(0.15)).interactive(), in: .rect(cornerRadius: 22))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                        if let fg = h.forGoal, !fg.isEmpty {
                            sectionTitle("Под вашу цель")
                            productRow(fg)
                        }
                        if let pop = h.popular, !pop.isEmpty {
                            sectionTitle("Популярное")
                            productGrid(pop)
                        }
                        if let stores = h.stores, !stores.isEmpty {
                            sectionTitle("Магазины в городе \(h.city ?? "")")
                            ForEach(stores) { s in
                                HStack(spacing: 12) {
                                    RemoteImage(url: API.media(s.logo), icon: "storefront.fill")
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name).font(.headline)
                                        if let d = s.description, !d.isEmpty {
                                            Text(d).font(.caption).foregroundStyle(Color.oxHint).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if let r = s.rating, r > 0 {
                                        Label(String(format: "%.1f", r), systemImage: "star.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .padding(12)
                                .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        }
                        if (h.popular ?? []).isEmpty && (h.stores ?? []).isEmpty {
                            ContentUnavailableView("Магазинов пока нет",
                                                   systemImage: "bag",
                                                   description: Text("В вашем городе ещё не подключены магазины спортпита"))
                        }
                    }
                } else if errorText == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 30)
        }
        .background(Color.oxBg)
        .navigationTitle("Магазин")
        .searchable(text: $query, prompt: "Протеин, креатин, бренд…")
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { if query.isEmpty { results = nil } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCart = true
                } label: {
                    Image(systemName: "cart.fill")
                        .overlay(alignment: .topTrailing) {
                            if cartCount > 0 {
                                Text("\(cartCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.black)
                                    .padding(4)
                                    .background(Color.lime, in: Circle())
                                    .offset(x: 10, y: -10)
                            }
                        }
                }
            }
        }
        .navigationDestination(item: $openProduct) { id in
            ProductView(productId: id) { n in cartCount = n }
        }
        .sheet(isPresented: $showCart) {
            CartView { n in cartCount = n } onCheckout: {
                showCart = false
                web = WebTarget(path: "/#mcart")
            }
        }
        .fullScreenCover(item: $web) { t in WebAppView(path: t.path) }
        .refreshable { await load() }
        .task { if home == nil { await load() } }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 16)
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
            HStack(spacing: 12) {
                ForEach(items) { p in
                    ProductTile(p: p) { openProduct = p.id }
                        .frame(width: 170)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func load() async {
        do {
            let h: ShopHome = try await API.call("/m/home")
            home = h
            cartCount = h.cartCount ?? 0
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func pickCategory(_ c: MCategory) async {
        Haptic.tap(.soft)
        if category?.id == c.id { category = nil; return }
        category = c
        catItems = []
        if let r: MCatalog = try? await API.call("/m/products", query: ["cat": String(c.id)]) {
            catItems = r.items
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

struct ProductTile: View {
    let p: MProduct
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RemoteImage(url: API.media(p.photo), icon: "takeoutbag.and.cup.and.straw.fill")
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if let old = p.oldPriceKop, let now = p.priceKop, old > now {
                        Text("−\(Int((1 - Double(now) / Double(old)) * 100))%")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.lime, in: Capsule())
                            .padding(8)
                    }
                }
                Text(p.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let b = p.brand, !b.isEmpty {
                    Text(b).font(.caption).foregroundStyle(Color.oxHint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rub(p.priceKop))
                        .font(.headline)
                    if let old = p.oldPriceKop, old > (p.priceKop ?? 0) {
                        Text(rub(old))
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(Color.oxHint)
                    }
                }
                if p.inStock == false {
                    Text("Нет в наличии").font(.caption).foregroundStyle(.red)
                }
            }
            .padding(10)
            .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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
                                RemoteImage(url: u).frame(height: 340).clipped()
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 340)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        if let b = p.brand, !b.isEmpty {
                            Text(b.uppercased()).font(.caption.bold()).foregroundStyle(Color.lime)
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
        .ignoresSafeArea(edges: .top)
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
                    .controlSize(.large)
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
                    .controlSize(.large)
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
            Haptic.tap(.soft)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func clear() async {
        if let c: MCart = try? await API.call("/m/cart", method: "DELETE") {
            cart = c
            onCount(c.count)
        }
    }
}
