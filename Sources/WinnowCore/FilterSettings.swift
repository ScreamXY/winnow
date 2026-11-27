import Foundation

/// The switches a person can change in the iOS Settings app (Settings → Apps → Winnow).
/// The keys match `Resources/Settings.bundle/Root.plist`. The defaults here must match it too,
/// because iOS does not register Settings bundle defaults by itself.
struct FilterSettings: Equatable, Sendable, Codable {
    /// Always open the Following feed instead of the algorithmic "For you" feed.
    var forceFollowing = true
    /// Hide the Reels tab and leave the algorithmic `/reels/` feed. Single reels stay.
    var hideReels = true
    /// Hide the algorithmic grid on the Explore page. Search stays.
    var hideExplore = true
    /// Hide "Suggested for you" accounts and suggested posts.
    var hideSuggestions = true
    /// Hide sponsored posts. Ads are chosen by the algorithm too.
    var hideSponsored = true
    /// Hide posts the person scrolled past before the page loaded, so the feed starts with new posts.
    var hideSeen = true
    /// Move one post per flick in the home feed.
    var flickMode = true
    /// Show the stories tray above the Following feed (it loads Instagram's home page in the background).
    var showStories = true

    enum Key {
        static let forceFollowing = "force_following"
        static let hideReels = "hide_reels"
        static let hideExplore = "hide_explore"
        static let hideSuggestions = "hide_suggestions"
        static let hideSponsored = "hide_sponsored"
        static let hideSeen = "hide_seen"
        static let flickMode = "flick_mode"
        static let showStories = "show_stories"
    }

    init() {}

    init(defaults: UserDefaults) {
        defaults.register(defaults: Self.registrationDefaults())
        forceFollowing = defaults.bool(forKey: Key.forceFollowing)
        hideReels = defaults.bool(forKey: Key.hideReels)
        hideExplore = defaults.bool(forKey: Key.hideExplore)
        hideSuggestions = defaults.bool(forKey: Key.hideSuggestions)
        hideSponsored = defaults.bool(forKey: Key.hideSponsored)
        hideSeen = defaults.bool(forKey: Key.hideSeen)
        flickMode = defaults.bool(forKey: Key.flickMode)
        showStories = defaults.bool(forKey: Key.showStories)
    }

    static func registrationDefaults() -> [String: Any] {
        let fallback = FilterSettings()
        return [
            Key.forceFollowing: fallback.forceFollowing,
            Key.hideReels: fallback.hideReels,
            Key.hideExplore: fallback.hideExplore,
            Key.hideSuggestions: fallback.hideSuggestions,
            Key.hideSponsored: fallback.hideSponsored,
            Key.hideSeen: fallback.hideSeen,
            Key.flickMode: fallback.flickMode,
            Key.showStories: fallback.showStories,
        ]
    }

    /// The settings as a JSON object for the injected page script.
    func javaScriptLiteral() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
