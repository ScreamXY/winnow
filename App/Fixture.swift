import Foundation
import WebKit

/// The hand-written test pages that UI tests load with `-WinnowFixture <name>`. Debug builds only.
enum Fixture {
    /// The page named by the launch argument, or nil outside UI tests.
    static var name: String? {
        #if DEBUG
            UserDefaults.standard.string(forKey: "WinnowFixture")
        #else
            nil
        #endif
    }

    /// The website data (login, cookies, page storage) of all web views. UI tests get an empty store
    /// that lives only as long as the app, so every test starts fresh and never touches the real login.
    @MainActor static let websiteDataStore: WKWebsiteDataStore = name == nil ? .default() : .nonPersistent()

    #if DEBUG
        /// The contents of `fixture-<file>.html` while UI tests run, or nil.
        static func html(_ file: String) -> String? {
            guard name != nil, let url = Bundle.main.url(forResource: "fixture-\(file)", withExtension: "html") else {
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }

        /// A script that stores post codes as seen today, in the page script's own format, before the
        /// page script reads them. UI tests pass the codes with `-WinnowSeenPosts a,b`.
        static var seenPostsScript: String? {
            guard name != nil, let list = UserDefaults.standard.string(forKey: "WinnowSeenPosts") else {
                return nil
            }
            let codes = list.split(separator: ",").map(String.init)
            guard let data = try? JSONEncoder().encode(codes), let literal = String(data: data, encoding: .utf8) else {
                return nil
            }
            return """
                (() => {
                  const day = Math.floor(Date.now() / 86400000);
                  const seen = Object.fromEntries(\(literal).map((code) => [code, day]));
                  localStorage.setItem('winnow.seenPosts', JSON.stringify(seen));
                })();
                """
        }
    #endif
}
