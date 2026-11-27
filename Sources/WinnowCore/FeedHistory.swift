import Foundation

/// Where the Home tab goes. Instagram's Home tab links to the "For you" feed; a fresh load of the
/// Following feed would start at the top again. When the feed is already in the web view's history,
/// going back to it keeps the page and the place in it, like the Home tab in Instagram's app.
enum FeedHistory {
    /// - Parameters:
    ///   - backList: The addresses before the current page, oldest first (`WKBackForwardList.backList`).
    ///   - settings: The feed the app shows depends on `forceFollowing`.
    /// - Returns: The index in `backList` of the newest entry that shows the feed, or nil when the feed
    ///   must load again.
    static func feedEntry(in backList: [URL], settings: FilterSettings) -> Int? {
        backList.lastIndex { url in
            // A plain "/" entry is the "For you" feed, which the app redirects and never shows.
            StoriesPolicy.isFeed(url) && RoutePolicy.decideInstagramPage(url, settings: settings) == .allow
        }
    }
}
