import Foundation

/// Makes the web view look like Safari. Without the `Version/… Safari/…` part, websites see
/// an "in-app browser" and may push the official app or limit features.
enum UserAgent {
    /// The value for `WKWebViewConfiguration.applicationNameForUserAgent`.
    /// Since iOS 26 the Safari version number matches the iOS major version.
    static func applicationName(isPad: Bool, systemVersion: String) -> String {
        let major = systemVersion.split(separator: ".").first.flatMap { Int($0) } ?? 26
        return isPad ? "Version/\(major).0 Safari/605.1.15" : "Version/\(major).0 Mobile/15E148 Safari/604.1"
    }
}
