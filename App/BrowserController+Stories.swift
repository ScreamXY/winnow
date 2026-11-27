import UIKit
import WebKit

// The stories tray above the Following feed. `StoriesStrip` loads the tray; this extension makes room
// for it above the list of posts (`setStoriesSpace` in `Web/winnow.js`) and moves it with the feed.
// A tapped story plays in the strip, which then covers the feed; the feed below keeps its place.

extension BrowserController {
    /// The tray belongs to the Following feed; without that feed, Instagram's own home has a tray.
    var storiesEnabled: Bool {
        settings.showStories && settings.forceFollowing
    }

    func setUpStories() {
        webView.addSubview(stories.container)
        stories.onTrayHeight = { [weak self] _ in
            self?.applyStoriesSpace()
        }
        stories.onOpen = { [weak self] url in
            self?.openFromStories(url)
        }
        stories.onStoryChanged = { [weak self] showing in
            self?.storyChanged(showing)
        }
        stories.mayLoad = { [weak self] in
            await self?.storiesMayLoad() ?? false
        }
    }

    /// The strip loads only on the feed and only after login. See `StoriesPolicy`.
    private func storiesMayLoad() async -> Bool {
        guard storiesEnabled, StoriesPolicy.isFeed(webView.url) else {
            return false
        }
        if Fixture.name != nil {
            return true
        }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return storiesEnabled && StoriesPolicy.mayLoad(mainPage: webView.url, cookies: cookies)
    }

    /// Unloads the strip when its page must not keep running: when the tray is switched off, on
    /// login, account and challenge pages, and after logout. See `StoriesPolicy.mayKeep`. Reads the
    /// cookies only when the address alone allows the strip.
    private func unloadStoriesIfNeeded() {
        guard stories.isLoaded, Fixture.name == nil else {
            return
        }
        guard storiesEnabled, StoriesPolicy.mayKeep(on: webView.url) else {
            stories.clear()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            if !StoriesPolicy.mayKeep(mainPage: webView.url, cookies: cookies) {
                stories.clear()
            }
        }
    }

    func reloadStories() {
        if storiesEnabled {
            stories.load()
        }
    }

    /// Makes room above the posts for the tray (or removes the room), then places the tray.
    func applyStoriesSpace() {
        let height = storiesEnabled ? Double(stories.trayHeight) : 0
        webView.callAsyncJavaScript(
            "return window.__winnow ? window.__winnow.setStoriesSpace(height) : null",
            arguments: ["height": height], in: nil, in: .defaultClient
        ) { [weak self] result in
            guard let self, case .success(let value) = result, let json = value as? String else {
                return
            }
            layout = try? JSONDecoder().decode(FeedLayout.self, from: Data(json.utf8))
            placeStories()
        }
    }

    /// Moves the tray with the feed. Runs on every scroll step, so it only sets frames.
    func placeStories() {
        let scrollView = webView.scrollView
        guard storiesEnabled, let layout, layout.route == "home", !layout.dialogOpen, let slot = layout.stories,
            scrollView.zoomScale > 0
        else {
            stories.place(frame: nil, clipTop: 0, in: webView.bounds)
            return
        }
        // Screen position = inset + (page position - scroll position) × zoom.
        let zoom = scrollView.zoomScale
        let insetTop = scrollView.adjustedContentInset.top
        let scrollY = (scrollView.contentOffset.y + insetTop) / zoom
        let frame = CGRect(
            x: slot.left * zoom, y: insetTop + (slot.top - scrollY) * zoom, width: slot.width * zoom,
            height: stories.trayHeight)
        stories.place(frame: frame, clipTop: insetTop + layout.topInset * zoom, in: webView.bounds)
    }

    /// Hides the tray away from the feed, unloads it when it must not run, and reloads it after a
    /// story was watched.
    func storiesAddressChanged(_ url: URL) {
        unloadStoriesIfNeeded()
        guard StoriesPolicy.isFeed(url) else {
            stories.place(frame: nil, clipTop: 0, in: webView.bounds)
            if StoriesPolicy.isStory(url) {
                visitedStories = true
            }
            return
        }
        guard storiesEnabled else {
            return
        }
        if visitedStories {
            visitedStories = false
            stories.load()
        } else if stories.trayHeight == 0 {
            // Instagram may open the feed without a full load, for example right after login.
            stories.reloadIfOlder(than: 10)
        }
        // Instagram draws the feed after the address changes; measure again a moment later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.applyStoriesSpace()
        }
    }

    /// A story opened or closed in the strip. While it plays, the page below must not take swipes
    /// (a swipe from the edge would go back in the feed's history) or VoiceOver.
    private func storyChanged(_ showing: Bool) {
        webView.allowsBackForwardNavigationGestures = !showing
        webView.scrollView.accessibilityElementsHidden = showing
        pageBackgroundChanged()
        if !showing {
            // The tray is back above the feed; place it again with a fresh layout.
            applyStoriesSpace()
        }
    }

    /// After `pageAddressChanged`, which already unloaded the strip if the tray is switched off.
    func storiesSettingsChanged() {
        if storiesEnabled, stories.trayHeight == 0 {
            stories.load()
        }
        applyStoriesSpace()
    }

    /// A link tapped in the strip (in the tray or in a story) opens in the main web view.
    private func openFromStories(_ url: URL) {
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
    }
}
