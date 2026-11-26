import UIKit
import WebKit

// The stories tray above the Following feed. `StoriesStrip` loads the tray; this extension makes room
// for it above the first post (`setStoriesSpace` in `Web/winnow.js`) and moves it with the feed.

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
    }

    func reloadStories() {
        if storiesEnabled {
            stories.load()
        }
    }

    /// Makes room above the first post for the tray (or removes the room), then places the tray.
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
        guard storiesEnabled, let layout, layout.route == "home", let slot = layout.stories,
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

    /// Hides the tray away from the feed, and reloads it after a story was watched.
    func storiesAddressChanged(_ url: URL) {
        let path = url.path(percentEncoded: false)
        guard path.isEmpty || path == "/" else {
            stories.place(frame: nil, clipTop: 0, in: webView.bounds)
            if path.hasPrefix("/stories/") {
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
        }
        // Instagram draws the feed after the address changes; measure again a moment later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.applyStoriesSpace()
        }
    }

    func storiesSettingsChanged() {
        if storiesEnabled, stories.trayHeight == 0 {
            stories.load()
        }
        applyStoriesSpace()
    }

    /// A story (or another page) tapped in the tray opens in the main web view.
    private func openFromStories(_ url: URL) {
        visitedStories = true
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
