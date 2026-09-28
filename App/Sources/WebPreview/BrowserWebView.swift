import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let url: URL
    let reloadCount: Int
    let onTitle: (String?) -> Void
    let onFailure: (any Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitle: onTitle, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.observeTitle(of: webView)
        context.coordinator.load(url, reloadCount: reloadCount, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTitle = onTitle
        context.coordinator.onFailure = onFailure
        context.coordinator.load(url, reloadCount: reloadCount, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        coordinator.titleObservation = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onTitle: (String?) -> Void
        var onFailure: (any Error) -> Void
        var titleObservation: NSKeyValueObservation?
        private var loadedURL: URL?
        private var loadedReloadCount: Int?

        init(onTitle: @escaping (String?) -> Void, onFailure: @escaping (any Error) -> Void) {
            self.onTitle = onTitle
            self.onFailure = onFailure
        }

        func observeTitle(of webView: WKWebView) {
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    self?.onTitle(webView.title)
                }
            }
        }

        func load(_ url: URL, reloadCount: Int, in webView: WKWebView) {
            if loadedURL != url {
                loadedURL = url
                loadedReloadCount = reloadCount
                webView.load(URLRequest(url: url))
            } else if loadedReloadCount != reloadCount {
                loadedReloadCount = reloadCount
                if webView.url == nil {
                    webView.load(URLRequest(url: url))
                } else {
                    webView.reload()
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
            report(error)
        }

        private func report(_ error: any Error) {
            let nsError = error as NSError
            guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
            onFailure(error)
        }
    }
}
