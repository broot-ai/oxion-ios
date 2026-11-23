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
        BrowserWindow.show()
        withAnimation(.spring(duration: 0.42, bounce: 0.12)) { mode = .open }
        Haptic.tap(.soft)
        return true
    }

    func expand() {
        BrowserWindow.show()
        withAnimation(.spring(duration: 0.42, bounce: 0.12)) { mode = .open }
    }

    func minimize() {
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) { mode = .minimized }
        BrowserWindow.releaseKey()
    }

    func close() {
        withAnimation(.smooth(duration: 0.3)) { mode = .hidden }
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
        observers = [
            wv.observe(\.estimatedProgress) { [weak self] w, _ in Task { @MainActor in self?.progress = w.estimatedProgress } },
            wv.observe(\.title) { [weak self] w, _ in Task { @MainActor in if let t = w.title, !t.isEmpty { self?.title = t } } },
            wv.observe(\.url) { [weak self] w, _ in Task { @MainActor in
                if let u = w.url { self?.url = u; self?.bookmarked = BrowserStore.isBookmarked(u.absoluteString) }
            } },
            wv.observe(\.isLoading) { [weak self] w, _ in Task { @MainActor in self?.loading = w.isLoading } },
            wv.observe(\.canGoBack) { [weak self] w, _ in Task { @MainActor in self?.canBack = w.canGoBack } },
            wv.observe(\.canGoForward) { [weak self] w, _ in Task { @MainActor in self?.canForward = w.canGoForward } },
        ]
        webView = wv
        return wv
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
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let v = super.hitTest(point, with: event)
            return v === rootViewController?.view ? nil : v
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

// MARK: - Интерфейс

struct BrowserHost: View {
    @State private var b = OxBrowser.shared
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                if b.mode == .open {
                    Color.black.opacity(0.35 * max(0, 1 - drag / 400))
                        .ignoresSafeArea()
                        .transition(.opacity)
                    BrowserPanel(drag: $drag)
                        .padding(.top, geo.safeAreaInsets.top + 6)
                        .offset(y: max(0, drag))
                        .transition(.move(edge: .bottom))
                        .ignoresSafeArea(edges: .bottom)
                } else if b.mode == .minimized {
                    BrowserMiniBar()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 62)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// свёрнутая страница — плашка над нижним меню
struct BrowserMiniBar: View {
    @State private var b = OxBrowser.shared
    var body: some View {
        HStack(spacing: 10) {
            Button { b.close() } label: {
                Image(systemName: "xmark").font(.subheadline.bold()).frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { b.expand() } label: {
                VStack(spacing: 0) {
                    Text(b.title.isEmpty ? "Один момент…" : b.title).font(.subheadline.bold()).lineLimit(1)
                    Text(b.url?.host() ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { b.expand() } label: {
                Image(systemName: "chevron.up").font(.subheadline.bold()).frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay(alignment: .bottom) {
            if b.loading {
                Capsule().fill(Color.lime).frame(height: 2).padding(.horizontal, 24)
                    .scaleEffect(x: max(0.05, b.progress), anchor: .leading)
            }
        }
        .gesture(DragGesture(minimumDistance: 10).onEnded { v in if v.translation.height < -30 { b.expand() } })
    }
}

struct BrowserPanel: View {
    @Binding var drag: CGFloat
    @State private var b = OxBrowser.shared
    @State private var editing = false
    @State private var address = ""
    @State private var showBookmarks = false
    @State private var shareItem: ShareBox?
    @FocusState private var addrFocused: Bool

    struct ShareBox: Identifiable { let id = UUID(); let items: [Any] }

    var body: some View {
        VStack(spacing: 0) {
            header
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { v in drag = max(0, v.translation.height) }
                    .onEnded { v in
                        if v.translation.height > 120 || v.predictedEndTranslation.height > 300 {
                            b.minimize()
                        }
                        withAnimation(.spring(duration: 0.35)) { drag = 0 }
                    })
            ZStack(alignment: .top) {
                if let wv = b.webView {
                    WebViewHost(webView: wv)
                }
                if b.loading {
                    GeometryReader { g in
                        Rectangle().fill(Color.lime)
                            .frame(width: g.size.width * max(0.05, b.progress), height: 2.5)
                            .animation(.smooth(duration: 0.2), value: b.progress)
                    }
                    .frame(height: 2.5)
                    .transition(.opacity)
                }
                if editing { addressSuggestions }
            }
            bottomBar
        }
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: -4)
        .sheet(isPresented: $showBookmarks) { BrowserBookmarksSheet() }
        .sheet(item: $shareItem) { s in ActivitySheet(items: s.items).presentationDetents([.medium, .large]) }
    }

    // MARK: шапка

    private var header: some View {
        HStack(spacing: 8) {
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
                        Button { address = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.primary.opacity(0.07), in: Capsule())
                Button("Отмена") { stopEditing() }.font(.subheadline)
            } else {
                Button { b.minimize() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in b.close() })
                .accessibilityLabel("Свернуть")
                Spacer(minLength: 0)
                Button { startEditing() } label: {
                    HStack(spacing: 5) {
                        if b.url?.scheme == "https" { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                        Text(b.url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                menu
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Capsule().fill(Color.primary.opacity(0.2)).frame(width: 36, height: 4).padding(.top, 3)
        }
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
                Button { if let u = b.url { shareItem = ShareBox(items: [u]) } } label: { Label("Поделиться", systemImage: "square.and.arrow.up") }
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        b.webView?.findInteraction?.presentFindNavigator(showingReplace: false)
                    }
                } label: { Label("Поиск на странице", systemImage: "magnifyingglass") }
                Button { UIPasteboard.general.url = b.url; Haptic.success() } label: { Label("Копировать ссылку", systemImage: "link") }
            }
            Section {
                Button { b.toggleBookmark() } label: {
                    Label(b.bookmarked ? "Убрать из закладок" : "Добавить в закладки", systemImage: b.bookmarked ? "bookmark.slash" : "bookmark")
                }
                Button { Task { await saveToFiles() } } label: { Label("Сохранить в Файлы", systemImage: "folder") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: последние посещения и закладки при вводе адреса

    private var addressSuggestions: some View {
        let q = address.trimmingCharacters(in: .whitespaces).lowercased()
        let hist = BrowserStore.history.filter { q.isEmpty || $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        let marks = BrowserStore.bookmarks.filter { q.isEmpty || $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        return List {
            if !hist.isEmpty {
                Section {
                    ForEach(hist.prefix(q.isEmpty ? 4 : 10)) { e in entryRow(e) }
                } header: {
                    HStack {
                        Text("Последние посещения")
                        Spacer()
                        Button("Очистить") { BrowserStore.clearHistory(); address = address + "" }.font(.caption)
                    }
                }
            }
            if !marks.isEmpty {
                Section("Закладки") { ForEach(marks) { e in entryRow(e) } }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemBackground))
    }

    private func entryRow(_ e: BrowserEntry) -> some View {
        Button {
            if let u = URL(string: e.url) { b.open(u) }
            stopEditing()
        } label: {
            HStack(spacing: 12) {
                Text(String((e.title.isEmpty ? (URL(string: e.url)?.host() ?? "?") : e.title).prefix(1)).uppercased())
                    .font(.headline).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Bubble.nameColor(abs(e.url.hashValue % 97)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title.isEmpty ? e.url : e.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(e.url.replacingOccurrences(of: "https://", with: "")).font(.caption).foregroundStyle(Color.limeInk).lineLimit(1)
                }
            }
        }
    }

    // MARK: нижняя панель

    private var bottomBar: some View {
        HStack {
            barButton("chevron.left", enabled: b.canBack) { b.webView?.goBack() }
            barButton("chevron.right", enabled: b.canForward) { b.webView?.goForward() }
            barButton("square.and.arrow.up") { if let u = b.url { shareItem = ShareBox(items: [u]) } }
            barButton(b.bookmarked ? "book.fill" : "book") { showBookmarks = true }
            barButton("safari") { openInSafari() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 26)
        .background(.bar)
    }

    private func barButton(_ icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap(.soft)
            action()
        } label: {
            Image(systemName: icon).font(.system(size: 19, weight: .regular)).frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.limeInk : Color.secondary.opacity(0.4))
        .disabled(!enabled)
    }

    // MARK: действия

    private func startEditing() {
        address = b.url?.absoluteString ?? ""
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
