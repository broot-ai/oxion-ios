import SwiftUI
import UIKit
import WebKit

/// Полная веб-версия Oxion внутри приложения — для разделов, которых ещё нет в родном интерфейсе
/// (маркетплейс, «Работа в Oxion», звонки, эфиры, панели). Вход переносится автоматически.
struct WebAppView: View {
    var path: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WebView(path: path, loading: $loading)
                .ignoresSafeArea(edges: .bottom)
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.trailing, 14)
            .padding(.top, 4)
        }
        .background(Color.black)
    }
}

private struct WebView: UIViewRepresentable {
    let path: String
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if let token = API.token,
           let data = try? JSONSerialization.data(withJSONObject: [token]),
           let arr = String(data: data, encoding: .utf8) {
            // PWA хранит вход в localStorage под ключом "token" — кладём туда токен приложения
            let js = "try { localStorage.setItem('token', \(arr)[0]); } catch (e) {}"
            config.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        var url = AppSettings.serverURL
        if !path.isEmpty { url = URL(string: AppSettings.serverURL.absoluteString + path) ?? url }
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }

        /// Ссылки на другие сайты (Telegram, карты, оплата) открываем снаружи
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            let ourHost = AppSettings.serverURL.host
            if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" || url.host == ourHost {
                decisionHandler(.allow)
            } else if navigationAction.targetFrame?.isMainFrame == false {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        /// target="_blank"
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if url.host == AppSettings.serverURL.host {
                    webView.load(URLRequest(url: url))
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }
    }
}
