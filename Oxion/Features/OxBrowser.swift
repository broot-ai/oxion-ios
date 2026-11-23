import SwiftUI
import WebKit
import SafariServices

// Встроенный браузер как в Telegram: ссылки открываются внутри Oxion. Сверху — крестик, адрес и «…»,
// снизу — назад/вперёд, поделиться, закладки, Safari. Свайп вниз по шапке сворачивает страницу в плашку.

// MARK: - Хранилище истории и закладок

struct BrowserEntry: Codable, Hashable, Identifiable {
    var url: String
    var title: String
    var id: String { url }
}

enum BrowserStore {
    private static let histKey = "ox.browser.history", markKey = "ox.browser.bookmarks"
    static var history: [BrowserEntry] { load(histKey) }
    static var bookmarks: [BrowserEntry] { load(markKey) }
    static func visit(_ e: BrowserEntry) {
        var h = history.filter { $0.url != e.url }
        h.insert(e, at: 0)
        save(Array(h.prefix(60)), histKey)
    }
    static func clearHistory() { save([], histKey) }
    static func isBookmarked(_ url: String) -> Bool { bookmarks.contains { $0.url == url } }
    static func toggleBookmark(_ e: BrowserEntry) {
        var b = bookmarks
        if let i = b.firstIndex(where: { $0.url == e.url }) { b.remove(at: i) } else { b.insert(e, at: 0) }
        save(b, markKey)
    }
    static func removeBookmark(_ url: String) { save(bookmarks.filter { $0.url != url }, markKey) }
    private static func load(_ k: String) -> [BrowserEntry] {
        guard let d = UserDefaults.standard.data(forKey: k), let v = try? JSONDecoder().decode([BrowserEntry].self, from: d) else { return [] }
        return v
    }
    private static func save(_ v: [BrowserEntry], _ k: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: k)
    }
}

// MARK: - Модель браузера

@MainActor @Observable
final class OxBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = OxBrowser()

    enum Mode { case hidden, open, minimized }
    var mode: Mode = .hidden
    var title = ""
    var url: URL?
    var progress: Double = 0
    var loading = false
    var canBack = false
    var canForward = false
    var zoom: Double = 1
    var bookmarked = false
    /// цвет шапки под цвет сайта, как в Telegram
    var pageColor: UIColor = .systemBackground
    /// снимок приложения: он «отъезжает назад», как экран под листом iOS
    var backdrop: UIImage?

    private(set) var webView: WKWebView?
    private var observers: [NSKeyValueObservation] = []

    /// включено ли открытие ссылок внутри приложения
    static var enabled: Bool { UserDefaults.standard.object(forKey: "ox.browser.inapp") as? Bool ?? true }

    /// открыть ссылку; true — открыли сами
    @discardableResult
    func open(_ u: URL) -> Bool {
        guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        let wv = webView ?? makeWebView()
        wv.load(URLRequest(url: u))
        url = u
        title = u.host() ?? ""
        zoom = 1
        wv.pageZoom = 1
        bookmarked = BrowserStore.isBookmarked(u.absoluteString)
        present()
        Haptic.tap(.soft)
        return true
    }

    func expand() { present() }

    /// как лист iOS: сначала снимок приложения, потом шторка выезжает снизу
    private func present() {
        if mode != .open { backdrop = BrowserWindow.snapshotApp() }
        BrowserWindow.show()
        guard mode != .open else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.5, bounce: 0)) { self.mode = .open }
        }
    }

    func minimize() {
        withAnimation(.spring(duration: 0.45, bounce: 0)) { mode = .minimized }
        BrowserWindow.releaseKey()
    }

    func close() {
        withAnimation(.spring(duration: 0.45, bounce: 0)) { mode = .hidden }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.mode == .hidden else { return }
            self.webView?.stopLoading()
            self.webView?.loadHTMLString("", baseURL: nil)
            self.webView = nil
            self.observers = []
            BrowserWindow.hide()
        }
    }

    func setZoom(_ z: Double) {
        zoom = min(2, max(0.5, (z * 10).rounded() / 10))
        webView?.pageZoom = zoom
    }

    func toggleBookmark() {
        guard let u = url else { return }
        BrowserStore.toggleBookmark(BrowserEntry(url: u.absoluteString, title: title))
        bookmarked = BrowserStore.isBookmarked(u.absoluteString)
        Haptic.success()
    }

    /// адресная строка: ссылка или поисковый запрос
    func go(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var target: URL?
        if t.contains("."), !t.contains(" ") {
            target = URL(string: t.hasPrefix("http") ? t : "https://" + t)
        }
        if target == nil {
            var c = URLComponents(string: "https://yandex.ru/search/")!
            c.queryItems = [.init(name: "text", value: t)]
            target = c.url
        }
        if let target { open(target) }
    }

    private func makeWebView() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.isFindInteractionEnabled = true
        wv.isInspectable = false
        wv.backgroundColor = .systemBackground
        pageColor = .systemBackground
        observers = [
            wv.observe(\.estimatedProgress) { [weak self] w, _ in Task { @MainActor in self?.progress = w.estimatedProgress } },
            wv.observe(\.title) { [weak self] w, _ in Task { @MainActor in if let t = w.title, !t.isEmpty { self?.title = t } } },
            wv.observe(\.url) { [weak self] w, _ in Task { @MainActor in
                if let u = w.url { self?.url = u; self?.bookmarked = BrowserStore.isBookmarked(u.absoluteString) }
            } },
            wv.observe(\.isLoading) { [weak self] w, _ in Task { @MainActor in self?.loading = w.isLoading } },
            wv.observe(\.canGoBack) { [weak self] w, _ in Task { @MainActor in self?.canBack = w.canGoBack } },
            wv.observe(\.canGoForward) { [weak self] w, _ in Task { @MainActor in self?.canForward = w.canGoForward } },
            wv.observe(\.themeColor) { [weak self] w, _ in Task { @MainActor in self?.updateColor(w) } },
            wv.observe(\.underPageBackgroundColor) { [weak self] w, _ in Task { @MainActor in self?.updateColor(w) } },
        ]
        webView = wv
        return wv
    }

    private func updateColor(_ w: WKWebView) {
        let c = w.themeColor ?? w.underPageBackgroundColor ?? .systemBackground
        withAnimation(.smooth(duration: 0.3)) { pageColor = c }
    }

    static func favicon(_ urlString: String) -> URL? {
        guard let h = URL(string: urlString)?.host() else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(h)")
    }

    // ссылки target=_blank открываем в этой же вкладке
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    // tel:, mailto:, App Store и ссылки других приложений — наружу
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let u = navigationAction.request.url, let s = u.scheme?.lowercased() else { decisionHandler(.allow); return }
        if ["http", "https", "about", "data", "blob", "file"].contains(s) { decisionHandler(.allow); return }
        Task { @MainActor in UIApplication.shared.open(u) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let u = webView.url else { return }
            BrowserStore.visit(BrowserEntry(url: u.absoluteString, title: webView.title ?? u.host() ?? ""))
        }
    }
}

// MARK: - Отдельное окно поверх приложения

@MainActor
enum BrowserWindow {
    private static var window: BrowserPassWindow?

    final class BrowserPassWindow: UIWindow {
        // пустые места пропускают нажатия в приложение (когда браузер свёрнут)
        // SwiftUI рисует кнопки внутри одного общего вида, поэтому решаем по режиму, а не по виду под пальцем:
        // открыт — окно ловит все нажатия; свёрнут — только плашку; скрыт — ничего
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let mode = MainActor.assumeIsolated { OxBrowser.shared.mode }
            switch mode {
            case .open:
                return super.hitTest(point, with: event)
            case .minimized:
                // плашка прижата к низу экрана, как в Telegram
                let h = 54 + safeAreaInsets.bottom
                let bar = CGRect(x: 0, y: bounds.height - h - 6, width: bounds.width, height: h + 6)
                return bar.contains(point) ? super.hitTest(point, with: event) : nil
            case .hidden:
                return nil
            }
        }
    }

    static func show() {
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else { return }
            let w = BrowserPassWindow(windowScene: scene)
            w.windowLevel = .normal + 2
            w.overrideUserInterfaceStyle = OxTheme.current.uiStyle
            let host = UIHostingController(rootView: BrowserHost().modifier(OxThemeModifier()))
            host.view.backgroundColor = .clear
            w.rootViewController = host
            w.backgroundColor = .clear
            window = w
        }
        window?.isHidden = false
        window?.makeKey()
    }

    /// снимок основного окна приложения
    static func snapshotApp() -> UIImage? {
        guard let w = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: { !($0 is BrowserPassWindow) && $0.windowLevel == .normal && !$0.isHidden }) else { return nil }
        let r = UIGraphicsImageRenderer(bounds: w.bounds)
        return r.image { _ in w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) }
    }

    static func releaseKey() {
        window?.resignKey()
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { !($0 is BrowserPassWindow) && $0.windowLevel == .normal }?.makeKey()
    }

    static func hide() {
        releaseKey()
        window?.isHidden = true
    }
}

// MARK: - Интерфейс (как в Telegram)

struct BrowserHost: View {
    @State private var b = OxBrowser.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let open = b.mode == .open
            // 0…1: насколько шторку стянули вниз
            let k = min(1, max(0, drag / max(1, geo.size.height * 0.6)))
            ZStack(alignment: .bottom) {
                if open {
                    // приложение «отъезжает назад» и скругляется — как под листом в iOS
                    Color.black.ignoresSafeArea().transition(.opacity)
                    if let img = b.backdrop {
                        Image(uiImage: img)
                            .resizable()
                            .ignoresSafeArea()
                            .clipShape(RoundedRectangle(cornerRadius: 40 + 14 * k, style: .continuous))
                            .scaleEffect(0.915 + 0.085 * k, anchor: .center)
                            .offset(y: 6 * (1 - k))
                            .brightness(-0.12 * (1 - k))
                            .ignoresSafeArea()
                            .transition(.scale(scale: 1.093).combined(with: .opacity))
                    }
                    BrowserPanel(drag: $drag)
                        .padding(.top, geo.safeAreaInsets.top + 12)
                        .offset(y: max(0, drag))
                        .transition(.move(edge: .bottom))
                        .ignoresSafeArea(edges: .bottom)
                } else if b.mode == .minimized {
                    BrowserMiniBar(bottomInset: geo.safeAreaInsets.bottom)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// свёрнутая страница — плашка внизу экрана, как в Telegram: крестик и название сайта
struct BrowserMiniBar: View {
    var bottomInset: CGFloat = 0
    @State private var b = OxBrowser.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(b.title.isEmpty ? "Один момент…" : b.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                HStack {
                    Button { b.close() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                            .frame(width: 48, height: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.leading, 6)
            }
            .frame(height: 54)
            Color.clear.frame(height: bottomInset)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))
        .overlay(alignment: .top) {
            if b.loading {
                GeometryReader { g in
                    Capsule().fill(Color.lime).frame(width: g.size.width * max(0.05, b.progress), height: 2.5)
                }
                .frame(height: 2.5)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: -2)
        .offset(y: min(0, drag) * 0.3)
        .contentShape(Rectangle())
        .onTapGesture { b.expand() }
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { v in drag = v.translation.height }
            .onEnded { v in
                if v.translation.height < -24 { b.expand() }
                withAnimation(.spring(duration: 0.3)) { drag = 0 }
            })
    }
}

/// значок сайта; если его нет — первая буква на оранжевом квадрате
struct BrowserFavicon: View {
    let url: String
    let title: String
    var size: CGFloat = 40
    var body: some View {
        let letter = String((title.isEmpty ? (URL(string: url)?.host() ?? "?") : title).prefix(1)).uppercased()
        AsyncImage(url: OxBrowser.favicon(url)) { phase in
            if let img = phase.image, phase.error == nil {
                img.resizable().interpolation(.high).scaledToFit()
                    .padding(size * 0.12)
                    .background(Color(.secondarySystemBackground))
            } else {
                Text(letter)
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: 0xF19A37))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct BrowserPanel: View {
    @Binding var drag: CGFloat
    @State private var b = OxBrowser.shared
    @State private var editing = false
    @State private var address = ""
    @State private var showMore = false
    @State private var showBookmarks = false
    @State private var shareChats = false
    @State private var shareItem: ShareBox?
    @State private var refresh = 0
    @FocusState private var addrFocused: Bool

    struct ShareBox: Identifiable { let id = UUID(); let items: [Any] }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                    .background(Color(.systemBackground))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 6)
                        .onChanged { v in if !editing { drag = max(0, v.translation.height) } }
                        .onEnded { v in
                            if !editing && (v.translation.height > 120 || v.predictedEndTranslation.height > 300) { b.minimize() }
                            withAnimation(.spring(duration: 0.35)) { drag = 0 }
                        })
                ZStack(alignment: .top) {
                    if let wv = b.webView { WebViewHost(webView: wv) }
                    if editing { addressSuggestions.transition(.opacity) }
                }
            }
            if !editing {
                bottomBar
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous))
        .overlay(alignment: .top) {
            // «ручка» шторки
            Capsule().fill(Color.primary.opacity(0.18)).frame(width: 38, height: 5).padding(.top, 6)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showBookmarks) { BrowserBookmarksSheet() }
        .sheet(isPresented: $shareChats) { if let u = b.url { ShareToChatsSheet(url: u) } }
        .sheet(item: $shareItem) { s in ActivitySheet(items: s.items).presentationDetents([.medium, .large]) }
    }

    // MARK: шапка: крестик · адрес · «…»

    private var header: some View {
        HStack(spacing: 10) {
            if editing {
                HStack(spacing: 6) {
                    TextField("Поиск или адрес сайта", text: $address)
                        .keyboardType(.webSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($addrFocused)
                        .submitLabel(.go)
                        .onSubmit { b.go(address); stopEditing() }
                    if !address.isEmpty {
                        Button { address = "" } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 18).padding(.trailing, 10)
                .frame(height: 50)
                .glassEffect(.regular.interactive(), in: .capsule)
                circle("xmark") { stopEditing() }
            } else {
                circle("xmark") { b.close() }
                Button { startEditing() } label: {
                    Text(b.url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay(alignment: .bottomLeading) {
                    // синяя полоска загрузки по низу адресной строки
                    if b.loading {
                        GeometryReader { g in
                            Capsule().fill(Color.lime)
                                .frame(width: max(14, (g.size.width - 40) * b.progress), height: 2.5)
                                .animation(.smooth(duration: 0.2), value: b.progress)
                        }
                        .frame(height: 2.5)
                        .padding(.leading, 20)
                        .padding(.bottom, 1)
                        .transition(.opacity)
                    }
                }
                menu
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func circle(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
                .frame(width: 50, height: 50).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var menu: some View {
        Menu {
            ControlGroup {
                Button { b.setZoom(b.zoom - 0.1) } label: { Text("A").font(.caption) }
                Button { b.setZoom(1) } label: { Text("\(Int((b.zoom * 100).rounded()))%") }
                Button { b.setZoom(b.zoom + 0.1) } label: { Text("A").font(.title3) }
            }
            .controlGroupStyle(.compactMenu)
            Section {
                Button { openInSafari() } label: { Label("Открыть в Safari", systemImage: "safari") }
            }
            Section {
                Button { b.webView?.reload() } label: { Label("Обновить", systemImage: "arrow.clockwise") }
                Button { shareChats = true } label: { Label("Поделиться", systemImage: "square.and.arrow.up") }
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        b.webView?.findInteraction?.presentFindNavigator(showingReplace: false)
                    }
                } label: { Label("Поиск", systemImage: "magnifyingglass") }
            }
            Section {
                Button { b.toggleBookmark() } label: {
                    Label(b.bookmarked ? "Убрать из закладок" : "Добавить в закладки", systemImage: b.bookmarked ? "bookmark.slash" : "book")
                }
                Button { Task { await saveToFiles() } } label: { Label("Сохранить в Файлы", systemImage: "folder") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: 50, height: 50).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: последние посещения и закладки

    private var addressSuggestions: some View {
        let q = address.trimmingCharacters(in: .whitespaces).lowercased()
        let typed = !q.isEmpty && q != (b.url?.absoluteString.lowercased() ?? "")
        let match: (BrowserEntry) -> Bool = { !typed || $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        let hist = BrowserStore.history.filter(match)
        let marks = BrowserStore.bookmarks.filter(match)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if !hist.isEmpty {
                    Section {
                        ForEach(Array(hist.prefix(showMore ? 40 : 3))) { e in entryRow(e) }
                        if hist.count > 3 && !showMore {
                            Button { withAnimation(.smooth) { showMore = true } } label: {
                                HStack(spacing: 18) {
                                    Image(systemName: "chevron.down").font(.title3).frame(width: 40)
                                    Text("Показать больше").font(.body)
                                }
                                .foregroundStyle(Color.blue)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            }
                        }
                    } header: {
                        sectionHeader("ПОСЛЕДНИЕ ПОСЕЩЕНИЯ") {
                            Button("Очистить") { BrowserStore.clearHistory(); refresh += 1 }
                                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                if !marks.isEmpty {
                    Section {
                        ForEach(marks) { e in entryRow(e) }
                    } header: { sectionHeader("ЗАКЛАДКИ") { EmptyView() } }
                }
            }
            .id(refresh)
        }
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionHeader<T: View>(_ t: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(t).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(Color(.secondarySystemBackground))
    }

    private func entryRow(_ e: BrowserEntry) -> some View {
        Button {
            if let u = URL(string: e.url) { b.open(u) }
            stopEditing()
        } label: {
            HStack(spacing: 14) {
                BrowserFavicon(url: e.url, title: e.title, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title.isEmpty ? e.url : e.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(e.url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "www.", with: ""))
                        .font(.subheadline).foregroundStyle(Color.blue).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 70) }
    }

    // MARK: нижняя стеклянная панель

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", enabled: b.canBack) { b.webView?.goBack() }
            barButton("chevron.right", enabled: b.canForward) { b.webView?.goForward() }
            barButton("square.and.arrow.up") { shareChats = true }
            barButton(b.bookmarked ? "bookmark.fill" : "bookmark") { showBookmarks = true }
            barButton("safari") { openInSafari() }
        }
        .padding(.horizontal, 8)
        .frame(width: 290, height: 56)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func barButton(_ icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap(.soft)
            action()
        } label: {
            Image(systemName: icon).font(.system(size: 21, weight: .regular))
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
    }

    // MARK: действия

    private func startEditing() {
        address = b.url?.absoluteString ?? ""
        showMore = false
        withAnimation(.smooth(duration: 0.25)) { editing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { addrFocused = true }
    }

    private func stopEditing() {
        addrFocused = false
        withAnimation(.smooth(duration: 0.25)) { editing = false }
    }

    private func openInSafari() {
        guard let u = b.url else { return }
        UIApplication.shared.open(u)
    }

    private func saveToFiles() async {
        guard let wv = b.webView else { return }
        do {
            let data = try await wv.pdf()
            let name = (b.title.isEmpty ? "Страница" : b.title).replacingOccurrences(of: "/", with: "-").prefix(60)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
            try data.write(to: file)
            shareItem = ShareBox(items: [file])
        } catch { OxAlert.error("Не удалось сохранить страницу") }
    }
}

// MARK: - «Поделиться»: ссылка в чаты Oxion, как в Telegram

struct ShareToChatsSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var chats: [ChatItem] = []
    @State private var picked: [Int] = []
    @State private var q = ""
    @State private var sending = false
    @State private var system = false
    @State private var loading = true
    @State private var loadError: String?

    private func loadChats() async {
        loading = true
        defer { loading = false }
        do {
            let r: ChatsResponse = try await API.call("/chats")
            withAnimation(.smooth(duration: 0.25)) { chats = r.items.filter { $0.archived != true } }
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }

    private var list: [ChatItem] {
        let s = q.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? chats : chats.filter { ($0.peer.name ?? "").localizedCaseInsensitiveContains(s) }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                roundButton("xmark") { dismiss() }
                Spacer()
                VStack(spacing: 1) {
                    Text("Поделиться").font(.headline)
                    Text(picked.isEmpty ? "Выберите чаты" : "Выбрано: \(picked.count)").font(.subheadline).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                roundButton("square.and.arrow.up") { system = true }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск", text: $q)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .glassEffect(.regular, in: .capsule)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 16) {
                    ForEach(list) { c in cell(c) }
                }
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .overlay(alignment: .bottom) {
            Button {
                if picked.isEmpty {
                    UIPasteboard.general.url = url
                    Haptic.success()
                    OxAlert.show(icon: "link", title: "Ссылка скопирована", message: url.host() ?? "")
                    dismiss()
                } else {
                    Task { await send() }
                }
            } label: {
                HStack {
                    if sending { ProgressView().tint(.white) }
                    Text(picked.isEmpty ? "Скопировать ссылку" : "Отправить").font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sending)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(34)
        .sheet(isPresented: $system) { ActivitySheet(items: [url]).presentationDetents([.medium, .large]) }
        .overlay {
            if loading { ProgressView() }
            else if let loadError { ContentUnavailableView("Чаты не загрузились", systemImage: "wifi.exclamationmark", description: Text(loadError)) }
            else if chats.isEmpty { ContentUnavailableView("Чатов пока нет", systemImage: "bubble.left.and.bubble.right") }
        }
        .task { await loadChats() }
        .animation(.smooth(duration: 0.2), value: picked)
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
                .frame(width: 50, height: 50).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private func cell(_ c: ChatItem) -> some View {
        let on = picked.contains(c.id)
        return Button {
            Haptic.tap(.soft)
            if let i = picked.firstIndex(of: c.id) { picked.remove(at: i) } else { picked.append(c.id) }
        } label: {
            VStack(spacing: 6) {
                Group {
                    if c.peer.group != nil {
                        GroupAvatar(photo: c.peer.photo, title: c.peer.name ?? "?", kind: c.peer.group, size: 70)
                    } else {
                        Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 70)
                    }
                }
                .scaleEffect(on ? 0.86 : 1)
                .overlay {
                    Circle().stroke(Color.blue, lineWidth: 2.5).frame(width: 78, height: 78).opacity(on ? 1 : 0)
                }
                .overlay(alignment: .bottomTrailing) {
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.blue)
                            .background(Circle().fill(Color(.systemBackground)).padding(-2))
                            .transition(.scale)
                    }
                }
                .frame(width: 78, height: 78)
                Text(c.peer.name ?? "Чат").font(.caption.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 32, alignment: .top)
            }
        }
        .buttonStyle(.plain)
    }

    private func send() async {
        sending = true
        defer { sending = false }
        var ok = 0
        for id in picked {
            if let _: Message = try? await API.call("/chats/\(id)/messages", method: "POST", body: ["text": url.absoluteString]) { ok += 1 }
        }
        if ok > 0 {
            OxSound.play(.sent)
            Haptic.success()
            OxAlert.show(icon: "paperplane.fill", title: "Отправлено", message: ok == 1 ? "Ссылка отправлена в чат" : "Ссылка отправлена в \(ok) чата")
            dismiss()
        } else {
            OxAlert.error("Не получилось отправить ссылку")
        }
    }
}

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct BrowserBookmarksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var marks = BrowserStore.bookmarks
    @State private var hist = BrowserStore.history
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $tab) {
                    Text("Закладки").tag(0)
                    Text("История").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                let list = tab == 0 ? marks : hist
                if list.isEmpty {
                    Text(tab == 0 ? "Закладок пока нет. Добавьте через «…» → «Добавить в закладки»." : "История пуста")
                        .foregroundStyle(.secondary)
                }
                ForEach(list) { e in
                    Button {
                        if let u = URL(string: e.url) { OxBrowser.shared.open(u) }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title.isEmpty ? e.url : e.title).foregroundStyle(.primary).lineLimit(1)
                            Text(e.url).font(.caption).foregroundStyle(Color.limeInk).lineLimit(1)
                        }
                    }
                    .swipeActions {
                        if tab == 0 {
                            Button(role: .destructive) {
                                BrowserStore.removeBookmark(e.url)
                                marks = BrowserStore.bookmarks
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                    }
                }
                if tab == 1 && !hist.isEmpty {
                    Button("Очистить историю", role: .destructive) { BrowserStore.clearHistory(); hist = [] }
                }
            }
            .navigationTitle(tab == 0 ? "Закладки" : "История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Ссылки в тексте становятся нажимаемыми

enum Linkify {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// дописать ссылки в уже размеченный текст (например, ответ ИИ с markdown)
    static func addLinks(_ a: inout AttributedString, color: Color? = nil) {
        guard let det = detector else { return }
        let s = String(a.characters)
        let ns = s as NSString
        for m in det.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let u = m.url, let r = Range(m.range, in: s) else { continue }
            let lo = a.characters.index(a.startIndex, offsetBy: s.distance(from: s.startIndex, to: r.lowerBound))
            let hi = a.characters.index(lo, offsetBy: s.distance(from: r.lowerBound, to: r.upperBound))
            if a[lo..<hi].runs.contains(where: { $0.link != nil }) { continue }
            a[lo..<hi].link = u
            if let color { a[lo..<hi].foregroundColor = color }
        }
    }

    static func attributed(_ s: String, color: Color? = nil, underline: Bool = false) -> AttributedString {
        var out = AttributedString(s)
        guard let det = detector else { return out }
        let ns = s as NSString
        for m in det.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let u = m.url, let r = Range(m.range, in: s),
                  let lo = AttributedString.Index(r.lowerBound, within: out),
                  let hi = AttributedString.Index(r.upperBound, within: out) else { continue }
            out[lo..<hi].link = u
            if let color { out[lo..<hi].foregroundColor = color }
            if underline { out[lo..<hi].underlineStyle = .single }
        }
        return out
    }
}

/// подключается к корню приложения: все ссылки http/https открываются во встроенном браузере
struct InAppBrowserLinks: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard OxBrowser.enabled, let s = url.scheme?.lowercased(), s == "http" || s == "https" else { return .systemAction }
            return OxBrowser.shared.open(url) ? .handled : .systemAction
        })
    }
}
