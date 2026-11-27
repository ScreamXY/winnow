import UIKit
import WebKit

/// The stories tray above the Following feed. Instagram's Following page has no tray, so a second,
/// small web view loads the home page, and `Web/stories.js` shows only its tray. Both web views
/// share the login (same website data store). A tap on a story opens it above the feed
/// (`StoryViewer`); other tapped links open in the main web view.
///
/// The strip loads only when `mayLoad` agrees (see `StoriesPolicy`): a load while the person is
/// logged out changes the shared `csrftoken` cookie and breaks the login in the main web view.
@MainActor
final class StoriesStrip: NSObject {
    /// Sits inside the main web view and clips the strip below Instagram's top bar.
    let container = StripContainer()
    let webView: WKWebView
    /// The tray height in points; 0 while no tray is found (for example when logged out).
    private(set) var trayHeight: CGFloat = 0
    /// Called when the tray height changes.
    var onTrayHeight: ((CGFloat) -> Void)?
    /// Called with a tapped address, such as a story. The app decides where it opens.
    var onOpen: ((URL) -> Void)?
    /// How often iOS ended the strip's process (usually low memory).
    private(set) var processTerminations = 0
    /// Asked before every load. Returns false while a load is not safe (logged out, or the main
    /// web view is not on the feed).
    var mayLoad: (@MainActor () async -> Bool)?

    private var urlObservation: NSKeyValueObservation?
    private var lastLoad = Date.distantPast
    /// Height used while the tray is not found yet, so Instagram lays out the page.
    private let searchHeight: CGFloat = 600

    init(applicationName: String?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        // The hidden For You posts must never start a video.
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.applicationNameForUserAgent = applicationName
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        super.init()

        let content = configuration.userContentController
        content.add(StripMessageProxy(owner: self), contentWorld: .defaultClient, name: "winnowStrip")
        if let source = Self.scriptSource() {
            content.addUserScript(
                WKUserScript(
                    source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        }

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        container.clipsToBounds = true
        container.isHidden = true
        container.addSubview(webView)

        // Instagram opens a story without a full page load; the address still changes.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.addressChanged(webView.url)
            }
        }
    }

    /// Loads Instagram's home page, which has the tray, when `mayLoad` agrees. Otherwise the strip
    /// stays empty.
    func load() {
        Task { [weak self] in
            guard let self else {
                return
            }
            guard await mayLoad?() ?? false else {
                clear()
                return
            }
            lastLoad = .now
            #if DEBUG
                if let html = Fixture.html("home") {
                    webView.loadHTMLString(html, baseURL: RoutePolicy.home)
                    return
                }
            #endif
            webView.load(URLRequest(url: RoutePolicy.home))
        }
    }

    /// True while an Instagram page (or one loading) is in the strip.
    var isLoaded: Bool {
        webView.url?.scheme == "https"
    }

    /// Reloads when the tray is older than `age`, so new stories and seen rings show up.
    func reloadIfOlder(than age: TimeInterval) {
        if Date.now.timeIntervalSince(lastLoad) > age {
            load()
        }
    }

    /// Empties the strip, so no Instagram page runs in it, and removes the tray.
    func clear() {
        lastLoad = .distantPast
        if isLoaded {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
        guard trayHeight != 0 else {
            return
        }
        trayHeight = 0
        onTrayHeight?(0)
    }

    /// Places the strip. All values are in the main web view's coordinates.
    /// - Parameters:
    ///   - frame: Where the tray belongs on screen (its top moves while the feed scrolls).
    ///   - clipTop: The bottom edge of Instagram's top bar; the strip is hidden above it.
    ///   - bounds: The main web view's bounds.
    func place(frame: CGRect?, clipTop: CGFloat, in bounds: CGRect) {
        // Hidden while there is no tray, and while the tray is fully under Instagram's top bar or below
        // the screen: then nobody can see it, and VoiceOver must not find it either.
        guard let frame, trayHeight > 0, frame.maxY > clipTop, frame.minY < bounds.height else {
            container.isHidden = true
            if frame == nil || trayHeight == 0 {
                webView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: searchHeight)
            }
            return
        }
        container.isHidden = false
        container.frame = CGRect(x: 0, y: clipTop, width: bounds.width, height: max(0, bounds.height - clipTop))
        webView.frame = CGRect(
            x: frame.minX, y: frame.minY - clipTop, width: frame.width, height: trayHeight)
    }

    /// Instagram opens a story in place (history.pushState). Move it to the main web view.
    private func addressChanged(_ url: URL?) {
        guard let url, url.scheme == "https", StoryViewer.isStory(url) else {
            return
        }
        onOpen?(url)
        if webView.canGoBack {
            webView.goBack()
        } else {
            // The tray loads again when the person comes back to the feed.
            clear()
        }
    }

    fileprivate func received(_ body: Any) {
        guard let message = body as? [String: Any], message["type"] as? String == "tray" else {
            return
        }
        let found = message["found"] as? Bool ?? false
        let height = CGFloat((message["height"] as? NSNumber)?.doubleValue ?? 0)
        let newHeight = found ? height : 0
        guard newHeight != trayHeight else {
            return
        }
        trayHeight = newHeight
        onTrayHeight?(newHeight)
    }

    private static func scriptSource() -> String? {
        guard let url = Bundle.main.url(forResource: "stories", withExtension: "js") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func isHome(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return path.isEmpty || path == "/"
    }

    /// Only story pages and tapped links may go from the strip to the main web view. A load or window
    /// that a script on the hidden For You page starts on its own is dropped.
    private static func mayForward(_ url: URL, _ action: WKNavigationAction) -> Bool {
        url.scheme == "https" && (action.navigationType == .linkActivated || StoryViewer.isStory(url))
    }
}

extension StoriesStrip: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame == true,
            url.scheme == "https", !Self.isHome(url)
        else {
            decisionHandler(.allow)
            return
        }
        // Only the home page loads here. A tapped link opens in the main web view. Other loads, such as
        // a redirect to the login page, are dropped: they must never take over the main web view.
        decisionHandler(.cancel)
        if Self.mayForward(url, navigationAction) {
            onOpen?(url)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processTerminations += 1
        load()
    }
}

extension StoriesStrip: WKUIDelegate {
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, Self.mayForward(url, navigationAction) {
            onOpen?(url)
        }
        return nil
    }
}

/// A view that lets touches outside its subviews pass through to the feed below.
final class StripContainer: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

/// WKUserContentController keeps a strong reference to its handlers. This proxy avoids a retain cycle.
private final class StripMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: StoriesStrip?

    init(owner: StoriesStrip) {
        self.owner = owner
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            owner?.received(message.body)
        }
    }
}
