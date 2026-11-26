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

    /// True for Instagram's home feed (`/`, with or without `?variant=…`).
    static func isFeed(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
            host == "instagram.com" || host.hasSuffix(".instagram.com")
        else {
            return false
        }
        let path = url.path(percentEncoded: false)
        return path.isEmpty || path == "/"
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
