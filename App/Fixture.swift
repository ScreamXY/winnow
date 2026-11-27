import Foundation

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

    #if DEBUG
        /// The contents of `fixture-<file>.html` while UI tests run, or nil.
        static func html(_ file: String) -> String? {
            guard name != nil, let url = Bundle.main.url(forResource: "fixture-\(file)", withExtension: "html") else {
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    #endif
}
