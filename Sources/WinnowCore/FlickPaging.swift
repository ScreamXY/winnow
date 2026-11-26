import Foundation

/// The feed layout that the page script reports. All values are CSS pixels in page
/// coordinates (0 is the top of the page).
struct FeedLayout: Equatable, Sendable, Decodable {
    struct Post: Equatable, Sendable, Decodable {
        var top: Double
        var height: Double
        var bottom: Double { top + height }
    }

    /// The page type, for example `home`. Flick mode only runs on `home`.
    var route: String
    var posts: [Post]
    /// Height of the fixed bar at the top of the page (0 if there is none).
    var topInset: Double
    /// Height of the fixed bar at the bottom of the page (0 if there is none).
    var bottomInset: Double
}

/// Flick mode: one flick moves exactly one post, like the full-screen feed that Instagram
/// tested in 2022. Posts taller than the screen can still be read with normal scrolling.
enum FlickPaging {
    /// Release speed (points per millisecond) that counts as a flick.
    static let flickVelocity = 0.25
    /// Small distance that still counts as "at the start of a post".
    static let tolerance = 2.0

    /// Where a scroll should come to rest after the finger lifts.
    ///
    /// - Parameters:
    ///   - layout: The latest post positions.
    ///   - scrollY: The page position now (top of the screen).
    ///   - proposedY: Where the scroll would stop without flick mode.
    ///   - viewportHeight: Visible page height.
    ///   - velocity: Release speed in points per millisecond. Positive means "towards newer posts".
    /// - Returns: The page position to stop at, or nil to keep normal scrolling.
    static func target(
        layout: FeedLayout, scrollY: Double, proposedY: Double, viewportHeight: Double, velocity: Double
    ) -> Double? {
        let posts = layout.posts.filter { $0.height > 1 }.sorted { $0.top < $1.top }
        let visibleHeight = viewportHeight - layout.topInset - layout.bottomInset
        guard !posts.isEmpty, visibleHeight > 0 else {
            return nil
        }
        // The line just below the top bar, and the line just above the bottom bar.
        let topLine = scrollY + layout.topInset
        let bottomLine = scrollY + viewportHeight - layout.bottomInset
        let current = posts.lastIndex { $0.top <= topLine + tolerance }
        func start(_ index: Int) -> Double { max(0, posts[index].top - layout.topInset) }
        func isTall(_ post: FeedLayout.Post) -> Bool { post.height > visibleHeight + tolerance }

        if velocity > flickVelocity {
            guard let index = current else {
                return start(0)
            }
            let post = posts[index]
            if isTall(post), post.bottom > bottomLine + tolerance {
                // Keep reading the tall post, but stop at its end.
                return min(proposedY, post.bottom - (viewportHeight - layout.bottomInset))
            }
            // After the last loaded post, scroll freely so Instagram can load more.
            return index + 1 < posts.count ? start(index + 1) : nil
        }

        if velocity < -flickVelocity {
            guard let index = current else {
                return nil
            }
            let post = posts[index]
            if topLine > post.top + tolerance {
                // Inside a post: go back to its start first.
                return isTall(post) ? max(proposedY, start(index)) : start(index)
            }
            // At the first post, go back to the very top (stories).
            return index > 0 ? start(index - 1) : 0
        }

        // A slow release settles on the nearest post start.
        guard let index = current else {
            return nil
        }
        let post = posts[index]
        if isTall(post), topLine > post.top + tolerance, post.bottom > bottomLine + tolerance {
            return nil
        }
        var candidates = [start(index)]
        if index + 1 < posts.count {
            candidates.append(start(index + 1))
        }
        return candidates.min { abs($0 - scrollY) < abs($1 - scrollY) }
    }
}
