import SwiftUI
import WebKit

/// Shows the served, themed page for the current post. Reloads when `reloadToken` changes
/// (after a rebuild) or when `url` changes (a different post is selected).
struct PreviewWebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        context.coordinator.lastToken = reloadToken
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if url != coordinator.loadedURL {
            coordinator.loadedURL = url
            coordinator.lastToken = reloadToken
            webView.load(URLRequest(url: url))
        } else if reloadToken != coordinator.lastToken {
            coordinator.lastToken = reloadToken
            webView.reloadFromOrigin()
        }
    }

    final class Coordinator {
        var loadedURL: URL?
        var lastToken = -1
    }
}
