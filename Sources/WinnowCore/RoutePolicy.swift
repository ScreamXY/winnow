import Foundation

/// What the web view should do with a page load.
enum RouteDecision: Equatable, Sendable {
    /// Load the page in the app.
    case allow
    /// Load another Instagram page instead.
    case redirect(URL)
    /// Open the address in the default browser or the matching app.
    case openExternally(URL)
    /// Do nothing. Used for `instagram://` links, which would open the official app.
    case block
}

/// Decides where a top-level page load may go. The page script hides things inside a page;
/// this policy keeps the person away from whole pages that are only algorithmic content.
enum RoutePolicy {
    static let home = URL(string: "https://www.instagram.com/")!
    static let followingFeed = URL(string: "https://www.instagram.com/?variant=following")!

    /// Feed variants that only show accounts the person chose.
    static let chosenFeedVariants: Set<String> = ["following", "favorites"]

    /// Hosts that stay inside the app. Instagram login and account flows can pass through
    /// Facebook and Meta pages, so those stay inside too.
    static let inAppDomains = ["instagram.com", "facebook.com", "meta.com", "fbsbx.com"]

    /// - Parameter userTappedLink: true when the person tapped a link. Only then do other
    ///   websites open outside the app; redirects during login stay inside.
    static func decide(_ url: URL, settings: FilterSettings, userTappedLink: Bool) -> RouteDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        switch scheme {
        case "http", "https":
            break
        case "about", "blob", "data":
            return .allow
        case "instagram":
            return .block
        default:
            // mailto:, tel:, maps and App Store links belong to other apps.
            return .openExternally(url)
        }
        guard let host = url.host()?.lowercased() else {
            return .allow
        }
        if host == "l.instagram.com" {
            return .openExternally(linkShimTarget(url) ?? url)
        }
        if !isInApp(host: host) {
            return userTappedLink ? .openExternally(url) : .allow
        }
        guard matches(host: host, domain: "instagram.com") else {
            return .allow
        }
        return decideInstagramPage(url, settings: settings)
    }

    /// Decision for an Instagram address that is already in the app.
    static func decideInstagramPage(_ url: URL, settings: FilterSettings) -> RouteDecision {
        let path = normalizedPath(url)
        if settings.forceFollowing, path == "/", !chosenFeedVariants.contains(queryValue("variant", in: url) ?? "") {
            return .redirect(followingFeed)
        }
        if settings.hideReels, path.hasPrefix("/reels/") {
            // `/reels/<code>/` is one reel inside the endless reels feed. Show it as a single reel.
            let parts = path.split(separator: "/")
            if parts.count == 2, isMediaCode(parts[1]) {
                return .redirect(URL(string: "https://www.instagram.com/reel/\(parts[1])/")!)
            }
            return .redirect(settings.forceFollowing ? followingFeed : home)
        }
        return .allow
    }

    /// Instagram wraps outgoing links as `https://l.instagram.com/?u=<target>`.
    static func linkShimTarget(_ url: URL) -> URL? {
        guard let value = queryValue("u", in: url), let target = URL(string: value),
            let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return target
    }

    static func isInApp(host: String) -> Bool {
        inAppDomains.contains { matches(host: host, domain: $0) }
    }

    private static func matches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        if path.isEmpty {
            return "/"
        }
        return path.hasSuffix("/") ? path : path + "/"
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    private static func isMediaCode(_ text: Substring) -> Bool {
        text != "audio" && !text.isEmpty
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

/// Stops redirect loops. If Instagram keeps sending the app back to a page that the app
/// redirects, the app gives up after a few tries and shows the page.
struct RedirectGuard: Sendable {
    var limit = 3
    var window: TimeInterval = 15
    private var recent: [Date] = []

    init(limit: Int = 3, window: TimeInterval = 15) {
        self.limit = limit
        self.window = window
    }

    /// Records a redirect and returns false when there were too many in the time window.
    mutating func allowRedirect(at now: Date) -> Bool {
        recent = recent.filter { now.timeIntervalSince($0) < window }
        guard recent.count < limit else {
            return false
        }
        recent.append(now)
        return true
    }
}
