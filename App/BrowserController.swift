import OSLog
import UIKit
import WebKit

/// Owns the web view that shows instagram.com and applies Winnow's rules to it:
/// - `RoutePolicy` decides which pages may load (Following feed, no reels feed, outside links).
/// - `Web/winnow.js` hides things inside a page.
/// - `FlickPaging` moves one post per flick in the home feed.
/// - `StoriesStrip` shows the stories tray above the Following feed (`BrowserController+Stories.swift`).
@MainActor
@Observable
final class BrowserController: NSObject {
    private(set) var isLoadingFirstPage = true
    private(set) var loadError: String?
    /// The page's background color, for the strip behind the status bar.
    private(set) var pageBackground = UIColor.systemBackground

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private(set) var settings: FilterSettings
    @ObservationIgnored var layout: FeedLayout?
    @ObservationIgnored let stories: StoriesStrip
    /// True after a story opened in the main web view (for example from a profile), so the tray
    /// reloads (seen rings) on return.
    @ObservationIgnored var visitedStories = false
    /// The page position when the finger touched down. A flick moves one post from here.
    @ObservationIgnored private var dragStartY: Double?
    /// How often iOS ended the page's process (usually low memory) and the page loaded again.
    @ObservationIgnored private(set) var processTerminations = 0
    @ObservationIgnored private var redirectGuard = RedirectGuard()
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    @ObservationIgnored private var backgroundObservation: NSKeyValueObservation?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let refreshControl = UIRefreshControl()
    @ObservationIgnored let log = Logger(subsystem: "com.screamxy.winnow", category: "browser")
    #if DEBUG
        @ObservationIgnored private var probe: DebugProbe?
        @ObservationIgnored private var flickLog: [[String: Any]] = []
    #endif

    override init() {
        settings = FilterSettings(defaults: .standard)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Fixture.websiteDataStore
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = UserAgent.applicationName(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            systemVersion: UIDevice.current.systemVersion)
        webView = WKWebView(frame: .zero, configuration: configuration)
        stories = StoriesStrip(
            applicationName: configuration.applicationNameForUserAgent, dataStore: configuration.websiteDataStore)
        super.init()
        setUpStories()

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
        refreshControl.addAction(
            UIAction { [weak self] _ in
                self?.webView.reload()
                self?.reloadStories()
            }, for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        // Instagram changes pages without a full load (history.pushState). The URL still changes.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.pageAddressChanged(webView.url)
            }
        }
        backgroundObservation = webView.observe(\.underPageBackgroundColor, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.pageBackgroundChanged()
            }
        }
        #if DEBUG
            probe = DebugProbe(webView: webView, strip: stories.webView) { [weak self] in self?.debugState() ?? [:] }
        #endif
    }

    // MARK: - Public actions

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        #if DEBUG
            if let name = Fixture.name, let html = Fixture.html(name) {
                // A hand-written test page. The base URL makes the page script treat it as Instagram.
                webView.loadHTMLString(html, baseURL: RoutePolicy.followingFeed)
                return
            }
        #endif
        load(RoutePolicy.feed(for: settings))
    }

    func retry() {
        loadError = nil
        if webView.url == nil {
            hasStarted = false
            start()
        } else {
            webView.reload()
        }
    }

    /// Called when the app comes to the front.
    func appBecameActive() {
        reloadSettings()
        if storiesEnabled {
            stories.reloadIfOlder(than: 300)
        }
    }

    /// Reads the Settings app values again.
    private func reloadSettings() {
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
        storiesSettingsChanged()
    }

    // MARK: - Page script

    private func installPageScript() {
        let content = webView.configuration.userContentController
        content.removeAllUserScripts()
        guard let script = Self.pageScriptSource(settings: settings) else {
            log.error("Page script is missing from the app bundle")
            return
        }
        #if DEBUG
            if let seeding = Fixture.seenPostsScript {
                // In the page script's world and before it: only scripts in one world run in order.
                content.addUserScript(
                    WKUserScript(
                        source: seeding, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
            }
        #endif
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

    /// The color behind the status bar: the page's, or black while a story covers the page.
    func pageBackgroundChanged() {
        pageBackground = stories.isShowingStory ? .black : webView.underPageBackgroundColor
    }

    // MARK: - Navigation

    func load(_ url: URL) {
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
        if !StoriesPolicy.isFeed(url) {
            // The feed layout belongs to the page before. Flick mode and the tray must not use it
            // before the page script reports the new page.
            layout = nil
        }
        storiesAddressChanged(url)
    }

    /// Returns false if the redirect was skipped to stop a loop. Goes back to the feed in the history.
    @discardableResult
    func redirect(to target: URL) -> Bool {
        guard redirectGuard.allowRedirect(at: .now) else {
            log.notice("Skipped redirect to \(target.absoluteString, privacy: .public) to stop a loop")
            return false
        }
        if target != RoutePolicy.feed(for: settings) || !goBackToFeed() {
            load(target)
        }
        return true
    }

    func openOutside(_ url: URL) {
        UIApplication.shared.open(url)
    }

    // MARK: - Feed layout (flick mode and the stories tray)

    func refreshLayout() {
        webView.callAsyncJavaScript(
            "return window.__winnow ? window.__winnow.layout() : null", arguments: [:], in: nil, in: .defaultClient
        ) { [weak self] result in
            guard let self, case .success(let value) = result, let json = value as? String else {
                return
            }
            layout = try? JSONDecoder().decode(FeedLayout.self, from: Data(json.utf8))
            placeStories()
        }
    }

    func showDialog(_ alert: UIAlertController) {
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
        // A full load resets the room for the tray. After a login, the tray may load now (the strip
        // checks the login and the page itself).
        applyStoriesSpace()
        if storiesEnabled, stories.trayHeight == 0 {
            stories.reloadIfOlder(than: 10)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processTerminations += 1
        log.notice("The page's process ended (\(self.processTerminations, privacy: .public) times); loading again")
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

// MARK: - UIScrollViewDelegate (flick mode)

extension BrowserController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        placeStories()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A fast stop makes one flick feel like one step. Other pages keep normal scrolling.
        let flicking = settings.flickMode && layout?.route == "home"
        scrollView.decelerationRate = flicking ? .fast : .normal
        dragStartY =
            scrollView.zoomScale > 0
            ? (scrollView.contentOffset.y + scrollView.adjustedContentInset.top) / scrollView.zoomScale : nil
        refreshLayout()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView, withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        #if DEBUG
            recordFlick(scrollView, velocity: velocity, proposed: targetContentOffset.pointee.y)
        #endif
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
                velocity: velocity.y, dragStartY: dragStartY)
        else {
            return
        }
        let maxOffset = max(-insets.top, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        targetContentOffset.pointee.y = min(max(target * zoom - insets.top, -insets.top), maxOffset)
        #if DEBUG
            flickLog[flickLog.count - 1]["target"] = targetContentOffset.pointee.y
        #endif
    }
}

#if DEBUG
    // MARK: - Debug probe state

    extension BrowserController {
        fileprivate func recordFlick(_ scrollView: UIScrollView, velocity: CGPoint, proposed: CGFloat) {
            flickLog.append([
                "offsetY": scrollView.contentOffset.y,
                "proposedY": proposed,
                "velocityY": velocity.y,
                "route": layout?.route ?? "none",
                "posts": layout?.posts.count ?? -1,
            ])
            flickLog = Array(flickLog.suffix(10))
        }

        fileprivate func debugState() -> [String: Any] {
            let scrollView = webView.scrollView
            let insets = scrollView.adjustedContentInset
            return [
                "url": webView.url?.absoluteString ?? "",
                "contentOffsetY": scrollView.contentOffset.y,
                "contentHeight": scrollView.contentSize.height,
                "boundsHeight": scrollView.bounds.height,
                "insetTop": insets.top,
                "insetBottom": insets.bottom,
                "zoom": scrollView.zoomScale,
                "flickMode": settings.flickMode,
                "layoutRoute": layout?.route ?? "none",
                "layoutPosts": layout?.posts.prefix(6).map { [$0.top, $0.height] } ?? [],
                "layoutTopInset": layout?.topInset ?? -1,
                "layoutBottomInset": layout?.bottomInset ?? -1,
                "flickLog": flickLog,
                "processTerminations": processTerminations,
                "stripProcessTerminations": stories.processTerminations,
                "storyOpen": stories.isShowingStory,
            ]
        }
    }
#endif
