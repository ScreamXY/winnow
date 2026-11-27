import Foundation

/// Decides when the stories strip may load Instagram's home page in its second web view.
///
/// Both web views share one cookie store. While the person is logged out, every load of the home
/// page sets a new `csrftoken` cookie. The login form in the main web view still sends the old
/// token, and Instagram rejects the login. So the strip loads only after login, and only while the
/// main web view shows the feed (never during login, two-factor or challenge pages).
enum StoriesPolicy {
    /// Instagram's login cookie. Winnow only checks that it exists; it never reads the value.
    static let sessionCookieName = "sessionid"

    /// - Parameters:
    ///   - mainPage: The address in the main web view.
    ///   - cookies: The cookies in the shared store.
    static func mayLoad(mainPage: URL?, cookies: [HTTPCookie]) -> Bool {
        isFeed(mainPage) && isLoggedIn(cookies: cookies)
    }

    /// Login, logout, two-factor and challenge pages. The strip unloads on them.
    private static let accountPathPrefixes = ["/accounts/", "/challenge/", "/auth_platform/"]

    /// Whether the strip may keep the page it already loaded while the main web view shows
    /// `mainPage`. Away from the feed the tray is hidden but kept, so it is ready on the way back.
    /// After a logout, and on account pages or other sites, it must unload: its scripts would keep
    /// sending requests and replace the shared `csrftoken` cookie.
    static func mayKeep(mainPage: URL?, cookies: [HTTPCookie]) -> Bool {
        mayKeep(on: mainPage) && isLoggedIn(cookies: cookies)
    }

    /// The part of `mayKeep` that needs no cookies: false on account pages and other sites.
    static func mayKeep(on mainPage: URL?) -> Bool {
        guard let path = instagramPath(mainPage) else {
            return false
        }
        return !accountPathPrefixes.contains { path.hasPrefix($0) }
    }

    /// True for Instagram's home feed (`/`, with or without `?variant=…`).
    static func isFeed(_ url: URL?) -> Bool {
        guard let path = instagramPath(url) else {
            return false
        }
        return path.isEmpty || path == "/"
    }

    /// True for one person's stories (`/stories/<name>/…`). The strip plays them in place.
    static func isStory(_ url: URL?) -> Bool {
        instagramPath(url)?.hasPrefix("/stories/") ?? false
    }

    /// The path of an `https` Instagram address, or nil for any other address.
    private static func instagramPath(_ url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
            host == "instagram.com" || host.hasSuffix(".instagram.com")
        else {
            return nil
        }
        return url.path(percentEncoded: false)
    }

    /// True when Instagram's login cookie is in the store.
    static func isLoggedIn(cookies: [HTTPCookie]) -> Bool {
        cookies.contains { cookie in
            let domain = cookie.domain.lowercased()
            return cookie.name == sessionCookieName
                && (domain == "instagram.com" || domain.hasSuffix(".instagram.com"))
        }
    }
}
