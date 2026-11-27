import Foundation
import Testing

@testable import WinnowCore

@Suite struct FeedHistoryTests {
    private func urls(_ paths: [String]) -> [URL] {
        paths.map { URL(string: "https://www.instagram.com\($0)")! }
    }

    @Test func goesBackToTheNewestFollowingFeed() {
        let back = urls(["/?variant=following", "/friend/", "/?variant=following", "/friend/p/abc/", "/other/"])
        #expect(FeedHistory.feedEntry(in: back, settings: FilterSettings()) == 2)
    }

    @Test func favoritesCountsAsTheFeed() {
        let back = urls(["/?variant=favorites", "/friend/"])
        #expect(FeedHistory.feedEntry(in: back, settings: FilterSettings()) == 0)
    }

    @Test func skipsTheForYouFeed() {
        // "/" is the "For you" feed. The app redirects it, so going back there would load the feed again.
        let back = urls(["/", "/friend/"])
        #expect(FeedHistory.feedEntry(in: back, settings: FilterSettings()) == nil)
        #expect(FeedHistory.feedEntry(in: urls(["/?variant=home"]), settings: FilterSettings()) == nil)
    }

    @Test func withoutForceFollowingAnyFeedCounts() {
        var settings = FilterSettings()
        settings.forceFollowing = false
        #expect(FeedHistory.feedEntry(in: urls(["/", "/friend/"]), settings: settings) == 0)
    }

    @Test func loadsTheFeedWhenItIsNotInTheHistory() {
        #expect(FeedHistory.feedEntry(in: [], settings: FilterSettings()) == nil)
        let back = urls(["/friend/", "/stories/friend/1/", "/explore/"])
        #expect(FeedHistory.feedEntry(in: back, settings: FilterSettings()) == nil)
        let other = [URL(string: "https://www.facebook.com/?variant=following")!]
        #expect(FeedHistory.feedEntry(in: other, settings: FilterSettings()) == nil)
    }

    @Test func theFeedFollowsTheSetting() {
        var settings = FilterSettings()
        #expect(RoutePolicy.feed(for: settings) == RoutePolicy.followingFeed)
        settings.forceFollowing = false
        #expect(RoutePolicy.feed(for: settings) == RoutePolicy.home)
    }
}
