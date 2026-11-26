import OSLog
import UIKit
import WebKit

/// Owns the web view that shows instagram.com and applies Winnow's rules to it:
/// - `RoutePolicy` decides which pages may load (Following feed, no reels feed, outside links).
/// - `Web/winnow.js` hides things inside a page.
/// - `FlickPaging` moves one post per flick in the home feed.
@MainActor
@Observable
final class BrowserController: NSObject {
    private(set) var isLoadingFirstPage = true
    private(set) var loadError: String?

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var settings: FilterSettings
    @ObservationIgnored private var layout: FeedLayout?
    @ObservationIgnored private var redirectGuard = RedirectGuard()
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let refreshControl = UIRefreshControl()
    @ObservationIgnored private let log = Logger(subsystem: "com.screamxy.winnow", category: "browser")

    override init() {
        settings = FilterSettings(defaults: .standard)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = UserAgent.applicationName(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            systemVersion: UIDevice.current.systemVersion)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        let content = configuration.userContentController
        content.add(ScriptMessageProxy(owner: self), contentWorld: .defaultClient, name: "winnow")
        installPageScript()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.delegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Lets Safari's Web Inspector (Develop menu on a Mac) inspect the page, to fix filters.
        webView.isInspectable = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        refreshControl.addAction(UIAction { [weak self] _ in self?.webView.reload() }, for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        // Instagram changes pages without a full load (history.pushState). The URL still changes.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.pageAddressChanged(webView.url)
            }
        }
    }

    // MARK: - Public actions

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        #if DEBUG
            if let html = Self.fixtureHTML() {
                // A hand-written test page. The base URL makes the page script treat it as Instagram.
                webView.loadHTMLString(html, baseURL: RoutePolicy.followingFeed)
                return
            }
        #endif
        load(settings.forceFollowing ? RoutePolicy.followingFeed : RoutePolicy.home)
    }

    #if DEBUG
        /// The test page named by the `-WinnowFixture <name>` launch argument (UI tests).
        private static func fixtureHTML() -> String? {
            guard let name = UserDefaults.standard.string(forKey: "WinnowFixture") else {
                return nil
            }
            guard let file = Bundle.main.url(forResource: "fixture-\(name)", withExtension: "html") else {
                return nil
            }
            return try? String(contentsOf: file, encoding: .utf8)
        }
    #endif

    func retry() {
        loadError = nil
        if webView.url == nil {
            hasStarted = false
            start()
        } else {
            webView.reload()
        }
    }

    /// Reads the Settings app values again. Called when the app becomes active.
    func reloadSettings() {
        let fresh = FilterSettings(defaults: .standard)
        guard fresh != settings else {
            return
        }
        settings = fresh
        installPageScript()
        webView.callAsyncJavaScript(
            "if (window.__winnow) { window.__winnow.configure(JSON.parse(config)); }",
            arguments: ["config": fresh.javaScriptLiteral()], in: nil, in: .defaultClient
        ) { _ in }
        pageAddressChanged(webView.url)
    }

    // MARK: - Page script

    private func installPageScript() {
        let content = webView.configuration.userContentController
        content.removeAllUserScripts()
        guard let script = Self.pageScriptSource(settings: settings) else {
            log.error("Page script is missing from the app bundle")
            return
        }
        content.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
    }

    private static func pageScriptSource(settings: FilterSettings) -> String? {
        guard let scriptURL = Bundle.main.url(forResource: "winnow", withExtension: "js"),
            let styleURL = Bundle.main.url(forResource: "winnow", withExtension: "css"),
            let script = try? String(contentsOf: scriptURL, encoding: .utf8),
            let style = try? String(contentsOf: styleURL, encoding: .utf8),
            let styleData = try? JSONEncoder().encode(style),
            let styleLiteral = String(data: styleData, encoding: .utf8)
        else {
            return nil
        }
        return "window.__winnowBoot = { config: \(settings.javaScriptLiteral()), css: \(styleLiteral) };\n" + script
    }

    // MARK: - Navigation

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    private func pageAddressChanged(_ url: URL?) {
        guard let url, url.scheme == "https" || url.scheme == "http" else {
            return
        }
        let decision = RoutePolicy.decide(url, settings: settings, userTappedLink: false)
        if case .redirect(let target) = decision, target != url {
            redirect(to: target)
        }
    }

    /// Returns false if the redirect was skipped to stop a loop.
    @discardableResult
    private func redirect(to target: URL) -> Bool {
        guard redirectGuard.allowRedirect(at: .now) else {
            log.notice("Skipped redirect to \(target.absoluteString, privacy: .public) to stop a loop")
            return false
        }
        load(target)
        return true
    }

    private func openOutside(_ url: URL) {
        UIApplication.shared.open(url)
    }

    // MARK: - Flick mode

    private func refreshLayout() {
        guard settings.flickMode else {
            layout = nil
            return
        }
        webView.callAsyncJavaScript(
            "return window.__winnow ? window.__winnow.layout() : null", arguments: [:], in: nil, in: .defaultClient
        ) { [weak self] result in
            guard let self, case .success(let value) = result, let json = value as? String else {
                return
            }
            layout = try? JSONDecoder().decode(FeedLayout.self, from: Data(json.utf8))
        }
    }

    private func showDialog(_ alert: UIAlertController) {
        var presenter = webView.window?.rootViewController
        while let next = presenter?.presentedViewController {
            presenter = next
        }
        presenter?.present(alert, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame == true else {
            // Frames inside a page (login checks, embeds) load normally. New windows go to the UI delegate.
            decisionHandler(.allow)
            return
        }
        let tapped = navigationAction.navigationType == .linkActivated
        switch RoutePolicy.decide(url, settings: settings, userTappedLink: tapped) {
        case .allow:
            decisionHandler(.allow)
        case .redirect(let target):
            if redirect(to: target) {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        case .openExternally(let target):
            decisionHandler(.cancel)
            openOutside(target)
        case .block:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoadingFirstPage = false
        loadError = nil
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func loadFailed(_ error: Error) {
        refreshControl.endRefreshing()
        let nsError = error as NSError
        // Cancelled loads are normal: a redirect or a new tap replaced them.
        let cancelled =
            (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
            || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
        guard !cancelled else {
            return
        }
        isLoadingFirstPage = false
        loadError = nsError.localizedDescription
    }
}

// MARK: - WKUIDelegate

extension BrowserController: WKUIDelegate {
    /// Links that open a new window (target=_blank, window.open).
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else {
            return nil
        }
        switch RoutePolicy.decide(url, settings: settings, userTappedLink: true) {
        case .allow:
            load(url)
        case .redirect(let target):
            redirect(to: target)
        case .openExternally(let target):
            openOutside(target)
        case .block:
            break
        }
        return nil
    }

    func webView(
        _ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        .prompt
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            showDialog(alert)
        }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: true) })
            showDialog(alert)
        }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: nil) })
            alert.addAction(
                UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                    continuation.resume(returning: alert?.textFields?.first?.text ?? "")
                })
            showDialog(alert)
        }
    }
}

// MARK: - UIScrollViewDelegate (flick mode)

extension BrowserController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        refreshLayout()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView, withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard settings.flickMode, let layout, layout.route == "home", scrollView.zoomScale > 0 else {
            return
        }
        // Page position = (content offset + inset) / zoom.
        let zoom = scrollView.zoomScale
        let insets = scrollView.adjustedContentInset
        let viewportHeight = (scrollView.bounds.height - insets.top - insets.bottom) / zoom
        let scrollY = (scrollView.contentOffset.y + insets.top) / zoom
        let proposedY = (targetContentOffset.pointee.y + insets.top) / zoom
        guard
            let target = FlickPaging.target(
                layout: layout, scrollY: scrollY, proposedY: proposedY, viewportHeight: viewportHeight,
                velocity: velocity.y)
        else {
            return
        }
        let maxOffset = max(-insets.top, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        targetContentOffset.pointee.y = min(max(target * zoom - insets.top, -insets.top), maxOffset)
    }
}

// MARK: - Messages from the page script

extension BrowserController {
    fileprivate func received(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else {
            return
        }
        log.debug("Page script: \(type, privacy: .public) \(String(describing: message["route"]), privacy: .public)")
    }
}

/// WKUserContentController keeps a strong reference to its handlers. This proxy avoids a retain cycle.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserController?

    init(owner: BrowserController) {
        self.owner = owner
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            owner?.received(message.body)
        }
    }
}
