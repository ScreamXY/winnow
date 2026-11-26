import Foundation
import Testing

@testable import WinnowCore

@Suite struct RoutePolicyTests {
    let settings = FilterSettings()

    private func decide(_ text: String, tapped: Bool = true, settings: FilterSettings? = nil) -> RouteDecision {
        RoutePolicy.decide(URL(string: text)!, settings: settings ?? self.settings, userTappedLink: tapped)
    }

    @Test func homeFeedOpensFollowing() {
        #expect(decide("https://www.instagram.com/") == .redirect(RoutePolicy.followingFeed))
        #expect(decide("https://www.instagram.com") == .redirect(RoutePolicy.followingFeed))
        #expect(decide("https://instagram.com/?variant=home") == .redirect(RoutePolicy.followingFeed))
    }

    @Test func chosenFeedsStay() {
        #expect(decide("https://www.instagram.com/?variant=following") == .allow)
        #expect(decide("https://www.instagram.com/?variant=favorites") == .allow)
    }

    @Test func homeFeedStaysWhenSwitchIsOff() {
        var relaxed = settings
        relaxed.forceFollowing = false
        #expect(decide("https://www.instagram.com/", settings: relaxed) == .allow)
    }

    @Test func reelsFeedIsLeft() {
        #expect(decide("https://www.instagram.com/reels/") == .redirect(RoutePolicy.followingFeed))
        #expect(decide("https://www.instagram.com/reels/audio/123/") == .redirect(RoutePolicy.followingFeed))
        #expect(
            decide("https://www.instagram.com/reels/C1a-B_2/")
                == .redirect(URL(string: "https://www.instagram.com/reel/C1a-B_2/")!))
    }

    @Test func singleReelsAndProfileReelsStay() {
        #expect(decide("https://www.instagram.com/reel/C1aB2/") == .allow)
        #expect(decide("https://www.instagram.com/some.friend/reel/C1aB2/") == .allow)
        #expect(decide("https://www.instagram.com/some.friend/reels/") == .allow)
    }

    @Test func reelsFeedStaysWhenSwitchIsOff() {
        var relaxed = settings
        relaxed.hideReels = false
        #expect(decide("https://www.instagram.com/reels/", settings: relaxed) == .allow)
    }

    @Test func reelsFeedGoesHomeWhenFollowingIsOff() {
        var relaxed = settings
        relaxed.forceFollowing = false
        #expect(decide("https://www.instagram.com/reels/", settings: relaxed) == .redirect(RoutePolicy.home))
    }

    @Test func explorePageStaysButIsFilteredInPage() {
        #expect(decide("https://www.instagram.com/explore/") == .allow)
        #expect(decide("https://www.instagram.com/explore/search/") == .allow)
        #expect(decide("https://www.instagram.com/explore/tags/running/") == .allow)
    }

    @Test func outgoingLinksOpenOutside() {
        let shim = "https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Fshop%3Fa%3D1&e=AT0"
        #expect(decide(shim) == .openExternally(URL(string: "https://example.com/shop?a=1")!))
        #expect(decide("https://example.com/") == .openExternally(URL(string: "https://example.com/")!))
        let threads = "https://www.threads.com/@someone"
        #expect(decide(threads) == .openExternally(URL(string: threads)!))
    }

    @Test func redirectsDuringLoginStayInside() {
        #expect(decide("https://example.com/", tapped: false) == .allow)
        #expect(decide("https://www.facebook.com/login/") == .allow)
        #expect(decide("https://accountscenter.meta.com/") == .allow)
        #expect(decide("https://www.instagram.com/accounts/login/") == .allow)
    }

    @Test func otherSchemes() {
        #expect(decide("instagram://user?username=x") == .block)
        #expect(decide("about:blank") == .allow)
        #expect(decide("mailto:hi@example.com") == .openExternally(URL(string: "mailto:hi@example.com")!))
    }

    @Test func redirectGuardStopsLoops() {
        var guardrail = RedirectGuard(limit: 3, window: 15)
        let start = Date(timeIntervalSince1970: 1000)
        let results = [0.0, 1, 2, 3, 20].map { guardrail.allowRedirect(at: start.addingTimeInterval($0)) }
        #expect(results == [true, true, true, false, true])
    }
}

@Suite struct SupportTests {
    @Test func userAgentLooksLikeSafari() {
        #expect(
            UserAgent.applicationName(isPad: false, systemVersion: "27.2")
                == "Version/27.0 Mobile/15E148 Safari/604.1")
        #expect(UserAgent.applicationName(isPad: true, systemVersion: "26.1") == "Version/26.0 Safari/605.1.15")
        #expect(
            UserAgent.applicationName(isPad: false, systemVersion: "x") == "Version/26.0 Mobile/15E148 Safari/604.1")
    }

    @Test func settingsReadDefaultsAndChanges() throws {
        let suite = "WinnowCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FilterSettings(defaults: defaults) == FilterSettings())
        defaults.set(false, forKey: FilterSettings.Key.hideSponsored)
        defaults.set(false, forKey: FilterSettings.Key.flickMode)
        let changed = FilterSettings(defaults: defaults)
        #expect(!changed.hideSponsored)
        #expect(!changed.flickMode)
        #expect(changed.forceFollowing)
    }

    @Test func settingsBecomeJavaScript() {
        let literal = FilterSettings().javaScriptLiteral()
        #expect(literal.contains("\"forceFollowing\":true"))
        #expect(literal.contains("\"hideSponsored\":true"))
    }
}
