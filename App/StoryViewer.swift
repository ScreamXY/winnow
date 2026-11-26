import UIKit
import WebKit

/// Shows a story full screen in its own web view, above the feed. The feed stays loaded below it,
/// so closing the story returns to the same place in the feed.
///
/// Opening the story in the main web view did not work well: on close, Instagram goes to "/", and
/// Winnow then loaded the Following feed again from the top.
@MainActor
final class StoryViewer: NSObject {
    let webView: WKWebView
    /// Called once when the person leaves the story. `next` is a page that belongs in the main web
    /// view (for example a profile), or nil when the story was just closed.
    var onClose: ((_ next: URL?) -> Void)?

    private var urlObservation: NSKeyValueObservation?
    private var isClosed = false

    init(url: URL, applicationName: String?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = applicationName
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // Instagram leaves a story without a full page load; the address still changes.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.addressChanged(webView.url)
            }
        }
        webView.load(URLRequest(url: url))
    }

    /// Removes the viewer. Safe to call more than once.
    func close(next: URL? = nil) {
        guard !isClosed else {
            return
        }
        isClosed = true
        urlObservation = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        onClose?(next)
    }

    static func isStory(_ url: URL) -> Bool {
        url.path(percentEncoded: false).hasPrefix("/stories/")
    }

    private static func isHome(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return path.isEmpty || path == "/"
    }

    /// Any page that is not a story ends the viewer: "/" means closed, other pages open in the feed.
    private func leave(to url: URL) {
        close(next: Self.isHome(url) ? nil : url)
    }

    private func addressChanged(_ url: URL?) {
        guard let url, url.scheme == "https" || url.scheme == "http", !Self.isStory(url) else {
            return
        }
        leave(to: url)
    }
}

extension StoryViewer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame == true,
            url.scheme == "https" || url.scheme == "http", !Self.isStory(url)
        else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        leave(to: url)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        close()
    }
}

extension StoryViewer: WKUIDelegate {
    /// Links that open a new window, such as a link sticker.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            close(next: url)
        }
        return nil
    }
}
